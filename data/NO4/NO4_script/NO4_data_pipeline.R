# -----------------------------------------------------------------------------
# 脚本名称: NO4_data_pipeline.R
# 功能: 数据预处理与轻量化转换流水线 (NO4 H5-Merge 定制版)
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
    library(futile.logger)
    library(Seurat)
    library(tidyverse)
    library(Matrix)
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
# 模块 A: 预处理 (Multiple H5 -> RDS)
# ==============================================================================
run_preprocess <- function(input_dir, output_rds) {
    setup_logging("pipeline_preprocess")
    flog.info(paste("Started PREPROCESS task. Input Dir:", input_dir))

    # 寻找 H5 文件
    h5_files <- list.files(input_dir, pattern = "\\.h5$", full.names = TRUE)
    if (length(h5_files) == 0) stop("No .h5 files found in input directory!")

    tryCatch(
        {
            scRNAlist <- list()

            # 1. 循环读取
            for (f in h5_files) {
                # 提取文件名作为 sample name (简单处理：去除后缀)
                s_name <- gsub("_filtered_feature_bc_matrix\\.h5$", "", basename(f))
                s_name <- gsub("\\.h5$", "", s_name)

                flog.info(paste("Reading sample:", s_name, "from", basename(f)))

                counts <- Read10X_h5(f)
                obj <- CreateSeuratObject(counts = counts, project = s_name)
                obj[["percent.mt"]] <- PercentageFeatureSet(obj, pattern = "^MT-")

                scRNAlist[[s_name]] <- obj
            }

            # 2. 合并
            flog.info("Merging samples...")
            if (length(scRNAlist) > 1) {
                merged <- merge(scRNAlist[[1]], y = scRNAlist[-1], add.cell.ids = names(scRNAlist))
            } else {
                merged <- scRNAlist[[1]]
            }
            rm(scRNAlist)
            invisible(gc())

            # Fix for Seurat V5: Join layers to strictly have one 'counts' layer for standard pipeline
            merged <- JoinLayers(merged)

            flog.info(paste("Total merged cells:", ncol(merged)))

            # 3. 过滤
            merged <- subset(merged, subset = nFeature_RNA > 200 & nCount_RNA > 500 & percent.mt < 20)
            flog.info(paste("Cells after filtering:", ncol(merged)))

            # 4. 分析流程
            flog.info("Running standard pipeline...")
            merged <- NormalizeData(merged)
            merged <- FindVariableFeatures(merged, selection.method = "vst", nfeatures = 2000)

            # Debug: Check Variable Features
            top_features <- VariableFeatures(merged)
            flog.info(paste("Number of variable features:", length(top_features)))
            if (length(top_features) == 0) stop("No variable features found!")

            # Debug: Inspect names
            all_genes <- rownames(merged)
            flog.info(paste("Example Genes:", paste(head(all_genes), collapse = ", ")))
            flog.info(paste("Example VarFeatures:", paste(head(top_features), collapse = ", ")))

            common <- intersect(top_features, all_genes)
            flog.info(paste("Intersect count:", length(common)))

            if (length(common) == 0) {
                flog.error("Fatal: Variable features do not match object rownames!")
                stop("Feature name mismatch")
            }

            merged <- ScaleData(merged)
            merged <- RunPCA(merged, features = top_features)
            merged <- RunUMAP(merged, dims = 1:20)
            merged <- FindNeighbors(merged, dims = 1:20)
            merged <- FindClusters(merged, resolution = 0.5)

            # 5. 元数据补充
            merged$cell_type <- paste0("Cluster", merged$seurat_clusters)
            merged$CD45_status <- "Unknown"

            # 6. 保存
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
            flog.info("Loading RDS...")
            seurat_obj <- readRDS(rds_path)

            # 1. 提取 Metadata
            flog.info("Extracting Metadata...")
            umap <- Embeddings(seurat_obj, "umap") %>% as.data.frame()
            colnames(umap) <- c("UMAP_1", "UMAP_2")

            meta <- seurat_obj@meta.data
            full_meta <- cbind(meta, umap)
            if (!"CellID" %in% colnames(full_meta)) full_meta$CellID <- rownames(full_meta)

            keep_cols <- c("orig.ident", "nCount_RNA", "nFeature_RNA", "percent.mt", "cell_type", "CD45_status", "UMAP_1", "UMAP_2", "seurat_clusters", "CellID")
            keep_cols <- keep_cols[keep_cols %in% colnames(full_meta)]
            lite_meta <- full_meta[, keep_cols]

            write.csv(lite_meta, file.path(output_dir, "metadata.csv"), row.names = FALSE)
            flog.info("Metadata saved.")

            # 1.5 生成基础图
            flog.info("Generating Base Plots...")
            base_dir <- file.path(output_dir, "base")
            if (!dir.exists(base_dir)) dir.create(base_dir)

            p_base_data <- lite_meta

            save_plot <- function(p, filename) {
                ggsave(file.path(base_dir, filename), p, width = 12, height = 10)
            }

            save_plot(ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = orig.ident)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Sample"), "uas.png")
            save_plot(ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = CD45_status)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: CD45 Status"), "ucd45.png")
            save_plot(ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = as.factor(seurat_clusters))) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Clusters") +
                guides(color = guide_legend(override.aes = list(size = 4))), "ucta_noanno.png")
            save_plot(ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = cell_type)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Cell Type") +
                guides(color = guide_legend(override.aes = list(size = 4))), "ucta_withanno.png")

            flog.info("Base plots generated.")

            # 2. 提取表达矩阵 (H5)
            flog.info("Converting Matrix to HDF5...")
            h5_path <- file.path(output_dir, "expression.h5")
            if (file.exists(h5_path)) file.remove(h5_path)
            h5createFile(h5_path)

            seurat_obj <- JoinLayers(seurat_obj)
            expr_mat <- GetAssayData(seurat_obj, layer = "data")

            genes <- rownames(expr_mat)
            cells <- colnames(expr_mat)

            h5write(genes, h5_path, "genes")
            h5write(cells, h5_path, "cells")

            flog.info("Writing H5 chunks...")
            h5createDataset(h5_path, "expression", c(length(genes), length(cells)), storage.mode = "double", chunk = c(200, length(cells)), level = 5)

            chunk_size <- 2000
            for (i in seq(1, length(genes), by = chunk_size)) {
                end_idx <- min(i + chunk_size - 1, length(genes))
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

# CLI
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript NO4_data_pipeline.R [preprocess|convert] ...")
action <- args[1]
input_val <- NULL
output_val <- NULL
for (i in seq_along(args)) {
    if (args[i] == "--input") input_val <- args[i + 1]
    if (args[i] == "--output") output_val <- args[i + 1]
}

if (action == "preprocess") {
    run_preprocess(input_val, output_val)
} else if (action == "convert") {
    run_convert(input_val, output_val)
}
