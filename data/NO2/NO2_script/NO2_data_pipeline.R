# -----------------------------------------------------------------------------
# 脚本名称: NO2_data_pipeline.R
# 功能: 数据预处理与轻量化转换流水线 (NO2 定制版)
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
            # raw_path 应该是包含 batch-org 文件夹的目录 (NO2 root)
            sample_dirs <- list.dirs(raw_path, full.names = TRUE, recursive = FALSE)
            # 过滤只保留包含 matrix.mtx.gz 的目录
            valid_samples <- c()
            for (d in sample_dirs) {
                if (file.exists(file.path(d, "matrix.mtx.gz"))) {
                    valid_samples <- c(valid_samples, d)
                }
            }

            if (length(valid_samples) == 0) stop("No valid 10x directories found!")

            scRNAlist <- list()
            for (s_path in valid_samples) {
                s_name <- basename(s_path)
                flog.info(paste("Reading sample:", s_name))
                counts <- Read10X(data.dir = s_path)
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

            # 3. 过滤
            merged <- subset(merged, subset = nFeature_RNA > 200 & nCount_RNA > 1000 & percent.mt < 50)

            # 4. 分析流程 (Normalize -> PCA -> UMAP)
            flog.info("Running normalization pipeline...")
            merged <- NormalizeData(merged, normalization.method = "LogNormalize", scale.factor = 10000)
            merged <- FindVariableFeatures(merged, selection.method = "vst", nfeatures = 2000)
            merged <- ScaleData(merged, features = VariableFeatures(merged))

            set.seed(123)
            merged <- RunPCA(merged, features = VariableFeatures(merged), npcs = 30)

            # Harmony integration if multiple batches (optional but recommended for multi-batch)
            if (length(valid_samples) > 1) {
                flog.info("Running Harmony integration...")
                merged <- RunHarmony(merged, "orig.ident")
                merged <- RunUMAP(merged, reduction = "harmony", dims = 1:30)
                merged <- FindNeighbors(merged, reduction = "harmony", dims = 1:30)
            } else {
                merged <- RunUMAP(merged, reduction = "pca", dims = 1:30)
                merged <- FindNeighbors(merged, dims = 1:30)
            }

            # 5. 聚类
            merged <- FindClusters(merged, resolution = 0.5)

            # 6. 注释 & 元数据补全
            # NO2 没有预定义的 annotation map，直接使用 Cluster ID
            merged$cell_type <- paste0("Cluster ", merged$seurat_clusters)
            merged$CD45_status <- "Unknown" # 填充默认值以兼容 Lite Plumber

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

            # 确保必要列存在
            if (!"CellID" %in% colnames(full_meta)) full_meta$CellID <- rownames(full_meta)

            keep_cols <- c(
                "orig.ident", "nCount_RNA", "nFeature_RNA", "percent.mt",
                "cell_type", "CD45_status", "UMAP_1", "UMAP_2", "seurat_clusters", "CellID"
            )
            # 交集保留
            keep_cols <- keep_cols[keep_cols %in% colnames(full_meta)]
            lite_meta <- full_meta[, keep_cols]

            meta_path <- file.path(output_dir, "metadata.csv")
            write.csv(lite_meta, meta_path, row.names = FALSE)
            flog.info("Metadata saved.")

            # 1.5 生成基础图
            flog.info("Generating Base Plots...")
            base_dir <- file.path(output_dir, "base")
            if (!dir.exists(base_dir)) dir.create(base_dir)

            p_base_data <- lite_meta

            # 1) UMAP by Sample
            p1 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = orig.ident)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Sample")
            ggsave(file.path(base_dir, "uas.png"), p1, width = 12, height = 10)

            # 2) UMAP by CD45 (Handle Unknown)
            p2 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = CD45_status)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: CD45 Status")
            # 如果全是 Unknown，颜色可能单一，但不会报错
            ggsave(file.path(base_dir, "ucd45.png"), p2, width = 12, height = 10)

            # 3) UMAP by Cluster
            p3 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = as.factor(seurat_clusters))) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Clusters") +
                guides(color = guide_legend(override.aes = list(size = 4)))
            ggsave(file.path(base_dir, "ucta_noanno.png"), p3, width = 12, height = 10)

            # 4) UMAP by CellType
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

            seurat_obj <- JoinLayers(seurat_obj)
            expr_mat <- GetAssayData(seurat_obj, layer = "data")

            genes <- rownames(expr_mat)
            cells <- colnames(expr_mat)

            h5write(genes, h5_path, "genes")
            h5write(cells, h5_path, "cells")

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

# CLI Entry
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
    cat("Usage: Rscript NO2_data_pipeline.R [preprocess|convert] [options]\n")
    quit(status = 0)
}
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
} else {
    stop("Unknown action")
}
