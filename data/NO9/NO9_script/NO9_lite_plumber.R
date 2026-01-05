# -----------------------------------------------------------------------------
# 脚本名称: NO9_lite_plumber.R
# 功能: 低内存消耗的微服务 (NO9 定制版)
# -----------------------------------------------------------------------------

library(plumber)
library(ggplot2)
library(rhdf5)
library(dplyr)
library(futile.logger)

# 配置
DATA_DIR <- Sys.getenv("LITE_DATA_DIR", file.path(getwd(), "../lite"))
META_FILE <- file.path(DATA_DIR, "metadata.csv")
H5_FILE <- file.path(DATA_DIR, "expression.h5")
CACHE_DIR <- file.path(DATA_DIR, "cache")

# 日志
log_dir <- "../logs/lite_service"
if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
flog.appender(appender.file(file.path(log_dir, "lite_service_no9.log")))
flog.threshold(INFO)

# 全局变量
META_DF <- NULL
GENE_INDEX <- NULL
GENE_MAP_UPPER <- NULL

# 启动
flog.info("Service starting (NO9)...")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

if (!file.exists(META_FILE) || !file.exists(H5_FILE)) {
    flog.warn(paste("Lite data files missing at", DATA_DIR))
} else {
    flog.info("Loading metadata...")
    META_DF <- read.csv(META_FILE, stringsAsFactors = FALSE)
    flog.info(paste("Metadata loaded:", nrow(META_DF), "cells"))

    all_genes <- h5read(H5_FILE, "genes")
    GENE_INDEX <- setNames(seq_along(all_genes), all_genes)
    GENE_MAP_UPPER <- setNames(all_genes, toupper(all_genes))
    flog.info("Service ready!")
}

get_gene_index <- function(gene_name) {
    idx <- GENE_INDEX[gene_name]
    if (!is.na(idx)) {
        return(list(name = gene_name, idx = idx))
    }
    real_name <- GENE_MAP_UPPER[toupper(gene_name)]
    if (!is.na(real_name)) {
        idx <- GENE_INDEX[real_name]
        return(list(name = real_name, idx = idx))
    }
    return(NULL)
}

get_base_plots_list <- function() {
    base_dir <- file.path(DATA_DIR, "base")
    if (!dir.exists(base_dir)) dir.create(base_dir, recursive = TRUE)

    paths <- list(
        uas = file.path(base_dir, "uas.png"),
        ucd45 = file.path(base_dir, "ucd45.png"),
        ucta_withanno = file.path(base_dir, "ucta_withanno.png"),
        ucta_noanno = file.path(base_dir, "ucta_noanno.png")
    )
    all_exist <- all(sapply(paths, function(x) file.exists(x) && file.size(x) > 0))

    if (!all_exist) {
        flog.info("Base plots regenerating...")
        p_base_data <- META_DF

        p1 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = orig.ident)) +
            geom_point(size = 0.5) +
            theme_void() +
            ggtitle("UMAP: Sample")
        ggsave(paths$uas, p1, width = 12, height = 10)

        p2 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = CD45_status)) +
            geom_point(size = 0.5) +
            theme_void() +
            ggtitle("UMAP: CD45 Status")
        ggsave(paths$ucd45, p2, width = 12, height = 10)

        p3 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = cell_type)) +
            geom_point(size = 0.5) +
            theme_void() +
            ggtitle("UMAP: Cell Type") +
            guides(color = guide_legend(override.aes = list(size = 4)))
        ggsave(paths$ucta_withanno, p3, width = 12, height = 10)

        p4 <- ggplot(p_base_data, aes(x = UMAP_1, y = UMAP_2, color = as.factor(seurat_clusters))) +
            geom_point(size = 0.5) +
            theme_void() +
            ggtitle("UMAP: Clusters") +
            guides(color = guide_legend(override.aes = list(size = 4)))
        ggsave(paths$ucta_noanno, p4, width = 12, height = 10)

        flog.info("Base plots regenerated.")
    }
    return(paths)
}

generate_gene_plots_list <- function(gene) {
    gene_info <- get_gene_index(gene)
    if (is.null(gene_info)) stop(paste("Gene", gene, "not found"))
    real_gene <- gene_info$name
    gene_idx <- gene_info$idx

    gene_dir <- file.path(CACHE_DIR, real_gene)
    if (!dir.exists(gene_dir)) dir.create(gene_dir, recursive = TRUE)

    paths <- list(
        feature = file.path(gene_dir, "feature_plot.png"),
        dot_withanno = file.path(gene_dir, "dot_plot_withanno.png"),
        dot_noanno = file.path(gene_dir, "dot_plot_noanno.png"),
        heat_withanno = file.path(gene_dir, "heat_plot_withanno.png"),
        heat_noanno = file.path(gene_dir, "heat_plot_noanno.png")
    )

    if (all(sapply(paths, function(x) file.exists(x) && file.size(x) > 0))) {
        flog.info(paste("Cache hit for gene:", real_gene))
        return(paths)
    }

    flog.info(paste("Cache miss. Generating:", real_gene))
    expr_vals <- as.vector(h5read(H5_FILE, "expression", index = list(gene_idx, NULL)))
    plot_data <- META_DF
    plot_data$Expression <- expr_vals

    # FeaturePlot
    p1 <- ggplot(plot_data %>% arrange(Expression), aes(x = UMAP_1, y = UMAP_2, color = Expression)) +
        geom_point(size = 0.5) +
        scale_color_gradient(low = "lightgrey", high = "red") +
        theme_void() +
        ggtitle(paste(real_gene, "Feature Plot"))
    ggsave(paths$feature, p1, width = 8, height = 6, dpi = 150)

    # DotPlot (Anno)
    dot_stats_anno <- plot_data %>%
        group_by(cell_type) %>%
        summarise(AvgExp = mean(exp(Expression) - 1), PctExp = mean(Expression > 0) * 100) %>%
        mutate(AvgExp = scale(AvgExp))
    p2a <- ggplot(dot_stats_anno, aes(x = cell_type, y = 1, size = PctExp, color = AvgExp)) +
        geom_point() +
        scale_color_gradient(low = "blue", high = "red") +
        theme_minimal() +
        coord_flip() +
        xlab("") +
        ylab("") +
        ggtitle(paste(real_gene, "Dot Plot (Annotated)"))
    ggsave(paths$dot_withanno, p2a, width = 6, height = 8, dpi = 150)

    # DotPlot (Cluster)
    dot_stats_noanno <- plot_data %>%
        group_by(seurat_clusters) %>%
        summarise(AvgExp = mean(exp(Expression) - 1), PctExp = mean(Expression > 0) * 100) %>%
        mutate(AvgExp = scale(AvgExp))
    p2b <- ggplot(dot_stats_noanno, aes(x = as.factor(seurat_clusters), y = 1, size = PctExp, color = AvgExp)) +
        geom_point() +
        scale_color_gradient(low = "blue", high = "red") +
        theme_minimal() +
        coord_flip() +
        xlab("Cluster") +
        ylab("") +
        ggtitle(paste(real_gene, "Dot Plot (Cluster)"))
    ggsave(paths$dot_noanno, p2b, width = 6, height = 8, dpi = 150)

    # Heatmaps (Unified)
    heat_data <- plot_data %>%
        mutate(ScaledExp = pmin(pmax(as.numeric(scale(Expression)), -2.5), 2.5))

    p3a <- ggplot(
        heat_data %>% arrange(cell_type, Expression) %>% mutate(CellRank = row_number()),
        aes(x = CellRank, y = 1, fill = ScaledExp)
    ) +
        geom_tile() +
        scale_fill_gradientn(colours = c("#1B7837", "white", "#762A83")) +
        theme_void() +
        ggtitle(paste(real_gene, "Heatmap (Annotated)")) +
        theme(legend.position = "bottom")
    ggsave(paths$heat_withanno, p3a, width = 10, height = 3, dpi = 150)

    p3b <- ggplot(
        heat_data %>% arrange(seurat_clusters, Expression) %>% mutate(CellRank = row_number()),
        aes(x = CellRank, y = 1, fill = ScaledExp)
    ) +
        geom_tile() +
        scale_fill_gradientn(colours = c("#1B7837", "white", "#762A83")) +
        theme_void() +
        ggtitle(paste(real_gene, "Heatmap (Cluster)")) +
        theme(legend.position = "bottom")
    ggsave(paths$heat_noanno, p3b, width = 10, height = 3, dpi = 150)

    return(paths)
}

# API
#* @get /health
function() list(status = "UP", mode = "Lite-H5-NO9")

#* 验证基因可用性
#* @param gene The gene name
#* @serializer json
#* @get /genes/check
function(gene, res) {
    if (is.null(get_gene_index(gene))) {
        res$status <- 440
        return(list(exists = FALSE, error = paste("Gene", gene, "not found")))
    }
    return(list(exists = TRUE, name = get_gene_index(gene)$name))
}

#* @serializer json
#* @get /plots/base
function() list(base_plots = get_base_plots_list())

#* @serializer json
#* @get /plots/gene
function(gene, res) {
    if (is.null(get_gene_index(gene))) {
        res$status <- 440
        return(list(error = paste("Gene", gene, "not found")))
    }
    tryCatch(
        {
            generate_gene_plots_list(gene)
            list(gene = gene, gene_plots = generate_gene_plots_list(gene))
        },
        error = function(e) {
            res$status <- 500
            list(error = e$message)
        }
    )
}

#* @serializer json
#* @get /plots/all
function(gene, res) {
    if (is.null(get_gene_index(gene))) {
        res$status <- 440
        return(list(error = paste("Gene", gene, "not found")))
    }
    tryCatch(
        {
            g <- generate_gene_plots_list(gene)
            b <- get_base_plots_list()
            list(gene = gene, gene_plots = g, base_plots = b)
        },
        error = function(e) {
            res$status <- 500
            list(error = e$message)
        }
    )
}
