# -----------------------------------------------------------------------------
# 脚本名称: NO1_data_pipeline.R
# 功能: 数据预处理与轻量化转换流水线（All-in-One）
# 作者: AntiGravity
# -----------------------------------------------------------------------------
# 依赖包检查: Seurat, tidyverse, Matrix, harmony, DoubletFinder, rhdf5, futile.logger
# 用法示例:
# 1. 预处理:
#    Rscript NO1_data_pipeline.R preprocess --input "/path/to/raw" --output "/path/to/obj.rds"
# 2. 转换:
#    Rscript NO1_data_pipeline.R convert --input "/path/to/obj.rds" --output "/path/to/lite_dir"
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
    library(futile.logger)
    library(Seurat)
    library(tidyverse)
    library(Matrix)
    library(harmony)
    library(rhdf5)
})

# 配置日志
setup_logging <- function(name) {
    log_dir <- file.path(getwd(), "logs")
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    log_file <- file.path(log_dir, paste0(name, "_", format(Sys.Date(), "%Y-%m-%d"), ".log"))
    flog.appender(appender.file(log_file))
    flog.threshold(INFO)
}

# ==============================================================================
# 模块 A: 预处理 (Raw -> RDS)
# ==============================================================================
run_preprocess <- function(raw_path, output_rds) {
    setup_logging("pipeline_preprocess")
    flog.info(paste("Started PREPROCESS task. Raw Path:", raw_path))

    tryCatch(
        {
            # 1. 设置 & 读取
            setwd(raw_path)
            samples <- list.dirs(full.names = TRUE, recursive = FALSE)
            samples <- samples[!grepl("visualizations", samples)]

            scRNAlist <- list()
            for (s_path in samples) {
                s_name <- basename(s_path)
                flog.info(paste("Reading sample:", s_name))
                counts <- Read10X(data.dir = s_path)
                obj <- CreateSeuratObject(counts = counts, project = s_name)
                obj[["percent.mt"]] <- PercentageFeatureSet(obj, pattern = "^MT-")

                # HB Genes
                hb_genes <- c("HBA1", "HBA2")
                hb_genes <- hb_genes[hb_genes %in% rownames(obj)]
                obj[["percent.hb"]] <- if (length(hb_genes) > 0) PercentageFeatureSet(obj, features = hb_genes) else 0

                scRNAlist[[s_name]] <- obj
            }

            # 2. 合并
            flog.info("Merging samples...")
            merged <- merge(scRNAlist[[1]], y = scRNAlist[-1], add.cell.ids = names(scRNAlist))
            rm(scRNAlist)
            invisible(gc())

            # 3. 过滤
            merged <- subset(merged, subset = nFeature_RNA > 200 & nCount_RNA > 1000 & percent.mt < 50)
            hb_genes <- c("HBA1", "HBA2")[c("HBA1", "HBA2") %in% rownames(merged)]
            if (length(hb_genes) > 0) {
                merged[["percent.hb"]] <- PercentageFeatureSet(merged, features = hb_genes)
                merged <- subset(merged, subset = percent.hb < 10)
            }

            # 4. 分析流程 (Normalize -> PCA -> UMAP)
            flog.info("Running normalization pipeline...")
            merged <- NormalizeData(merged, normalization.method = "LogNormalize", scale.factor = 10000)
            merged <- FindVariableFeatures(merged, selection.method = "vst", nfeatures = 2000)
            merged <- ScaleData(merged, features = VariableFeatures(merged))

            set.seed(123)
            merged <- RunPCA(merged, features = VariableFeatures(merged), npcs = 30)
            merged <- RunUMAP(merged, reduction = "pca", dims = 1:30)

            # 5. 特殊处理 (Varimax + CD45)
            flog.info("Applying specialized processing (Varimax)...")
            cd45_pos <- c(
                "GSM6094652", "GSM6094653", "GSM6094654", "GSM6094666",
                "GSM6094660", "GSM6094661", "GSM6094662", "GSM6094663",
                "GSM6094664", "GSM6094665"
            )
            merged$CD45_status <- ifelse(merged$orig.ident %in% cd45_pos, "CD45 Positive", "Normal")

            pca_loadings <- merged[["pca"]]@feature.loadings
            tryCatch(
                {
                    varimax_res <- varimax(pca_loadings)
                    colnames(varimax_res$rotmat) <- colnames(pca_loadings)
                    merged[["pca"]]@feature.loadings <- varimax_res$rotmat
                    merged <- RunUMAP(merged, dims = 1:20) # Re-run UMAP after rotation
                },
                error = function(e) {
                    flog.warn(paste("Varimax rotation failed, using default PCA:", e$message))
                }
            )

            # 6. 聚类 & 注释
            merged <- FindNeighbors(merged, dims = 1:20)
            merged <- FindClusters(merged, resolution = 0.7)

            anno_map <- c(
                "0" = "Proximal Tubular Cells", "1" = "Proximal Tubular Cells", "2" = "Proximal Tubular Cells",
                "3" = "Proximal Tubular Cells", "4" = "Proximal Tubular Cells", "5" = "Proximal Tubular Cells",
                "6" = "Proximal Tubular Cells", "11" = "Proximal Tubular Cells", "13" = "Proximal Tubular Cells",
                "19" = "Proximal Tubular Cells", "20" = "Proximal Tubular Cells", "14" = "Endothelial Cells",
                "9" = "NK Cells", "10" = "T Cells", "23" = "B Cells", "15" = "MNPs (Mononuclear Phagocytes)",
                "16" = "MNPs (Mononuclear Phagocytes)", "18" = "MNPs (Mononuclear Phagocytes)",
                "12" = "DCT (Distal Convoluted Tubule) Cells", "7" = "cTAL (Cortical Thick Ascending Limb) Cells",
                "22" = "MES (Mesenchymal) Cells", "17" = "Collecting Duct Cells", "8" = "Undefined Cells", "21" = "Undefined Cells"
            )

            merged$seurat_clusters <- as.character(merged$seurat_clusters)
            merged$cell_type <- unname(anno_map[merged$seurat_clusters])
            merged$cell_type[is.na(merged$cell_type)] <- "Unknown"
            merged$cell_type <- factor(merged$cell_type)

            # 7. 保存
            flog.info(paste("Saving to RDS:", output_rds))
            saveRDS(merged, file = output_rds)
            flog.info("PREPROCESS task completed successfully.")
        },
        error = function(e) {
            flog.error(paste("Preprocess failed:", e$message))
            quit(status = 1)
        }
    )
}

# ==============================================================================
# 模块 B: 轻量化转换 (RDS -> H5+CSV)
# ==============================================================================
run_convert <- function(rds_path, output_dir) {
    setup_logging("pipeline_convert")
    flog.info(paste("Started CONVERT task. RDS Path:", rds_path))

    if (!file.exists(rds_path)) stop("Input RDS file missing!")
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

    tryCatch(
        {
            flog.info("Loading RDS (Heavy I/O)...")
            seurat_obj <- readRDS(rds_path)

            # 1. 提取 Metadata (CSV)
            flog.info("Extracting Metadata...")
            umap <- Embeddings(seurat_obj, "umap") %>% as.data.frame()
            colnames(umap) <- c("UMAP_1", "UMAP_2")

            meta <- seurat_obj@meta.data
            full_meta <- cbind(meta, umap)

            # 选择关键列 (增加 seurat_clusters)
            keep_cols <- c(
                "orig.ident", "nCount_RNA", "nFeature_RNA", "percent.mt",
                "cell_type", "CD45_status", "UMAP_1", "UMAP_2", "seurat_clusters"
            )
            keep_cols <- keep_cols[keep_cols %in% colnames(full_meta)]
            lite_meta <- full_meta[, keep_cols]
            lite_meta$CellID <- rownames(lite_meta)

            meta_path <- file.path(output_dir, "metadata.csv")
            write.csv(lite_meta, meta_path, row.names = FALSE)
            flog.info("Metadata saved.")

            # 1.5 生成基础图 (Base Plots) - 仅生成一次
            flog.info("Generating Base Plots...")
            base_dir <- file.path(output_dir, "base")
            if (!dir.exists(base_dir)) dir.create(base_dir)

            # 为了画图，构建简单的 ggplot 对象 (无需 Seurat 依赖)
            p_base_data <- lite_meta

            # 1) UMAP by Sample
            p1 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = orig.ident)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Sample")
            ggsave(file.path(base_dir, "uas.png"), p1, width = 12, height = 10)

            # 2) UMAP by CD45
            p2 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = CD45_status)) +
                geom_point(size = 0.5) +
                scale_color_manual(values = c("red", "blue")) +
                theme_void() +
                ggtitle("UMAP: CD45 Status")
            ggsave(file.path(base_dir, "ucd45.png"), p2, width = 12, height = 10)

            # 3) UMAP by Cluster (NoAnno)
            p3 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = as.factor(seurat_clusters))) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Clusters") +
                guides(color = guide_legend(override.aes = list(size = 4)))
            ggsave(file.path(base_dir, "ucta_noanno.png"), p3, width = 12, height = 10)

            # 4) UMAP by CellType (WithAnno)
            p4 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = cell_type)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Cell Type") +
                guides(color = guide_legend(override.aes = list(size = 4)))
            ggsave(file.path(base_dir, "ucta_withanno.png"), p4, width = 12, height = 10)

            flog.info("Base plots generated.")

            # 2. 提取表达矩阵 (H5)
            flog.info("Converting Matrix to HDF5...")
            h5_path <- file.path(output_dir, "expression.h5")
            if (file.exists(h5_path)) file.remove(h5_path)
            h5createFile(h5_path)

            # V5 兼容: Join Layers
            seurat_obj <- JoinLayers(seurat_obj)
            expr_mat <- GetAssayData(seurat_obj, layer = "data")

            genes <- rownames(expr_mat)
            cells <- colnames(expr_mat)

            h5write(genes, h5_path, "genes")
            h5write(cells, h5_path, "cells")

            # 分块写入
            flog.info("Writing H5 chunks...")
            h5createDataset(h5_path, "expression", c(length(genes), length(cells)),
                storage.mode = "double", chunk = c(200, length(cells)), level = 5
            )

            chunk_size <- 2000
            n_genes <- length(genes)

            for (i in seq(1, n_genes, by = chunk_size)) {
                end_idx <- min(i + chunk_size - 1, n_genes)
                if (i %% 10000 == 1) flog.info(paste("Processing genes", i, "-", end_idx))

                sub_mat <- as.matrix(expr_mat[i:end_idx, , drop = FALSE])
                h5write(sub_mat, h5_path, "expression", index = list(i:end_idx, NULL))
                rm(sub_mat)
                invisible(gc())
            }

            H5close()
            flog.info(paste("CONVERT task completed. Output at:", output_dir))
        },
        error = function(e) {
            flog.error(paste("Convert failed:", e$message))
            quit(status = 1)
        }
    )
}

# ==============================================================================
# 命令行入口
# ==============================================================================
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
    cat("Usage: Rscript NO1_data_pipeline.R [preprocess|convert] [options]\n")
    cat("  preprocess --input <dir> --output <file.rds>\n")
    cat("  convert    --input <file.rds> --output <dir>\n")
    quit(status = 0)
}

action <- args[1]
input_val <- NULL
output_val <- NULL

# 简单参数解析
for (i in seq_along(args)) {
    if (args[i] == "--input") input_val <- args[i + 1]
    if (args[i] == "--output") output_val <- args[i + 1]
}

if (is.null(input_val) || is.null(output_val)) {
    stop("Missing --input or --output arguments")
}

if (action == "preprocess") {
    run_preprocess(input_val, output_val)
} else if (action == "convert") {
    run_convert(input_val, output_val)
} else {
    stop(paste("Unknown action:", action))
}
