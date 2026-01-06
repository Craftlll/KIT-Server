# R/utils_plot.R
library(ggplot2)
library(dplyr)
# Fix linter warnings
utils::globalVariables(c("UMAP_1", "UMAP_2", "Expression", "cell_type", "seurat_clusters", "AvgExp", "PctExp", "ScaledExp", "CellRank"))

#' Batch Generate, Cache, and Return Base64 Plots
#' @param ctx Dataset context
#' @param gene Gene name
#' @return List of base64 encoded strings
process_gene_plots <- function(ctx, gene) {
    # 1. Resolve Gene
    real_gene <- check_gene_exists(ctx, gene)
    if (is.null(real_gene)) {
        return(NULL)
    }

    # 2. Determine Plan based on Capabilities
    # Always include Feature Plot
    targets <- list(feature = "feature")

    if (isTRUE(ctx$capabilities$has_anno)) {
        targets$dot_anno <- "dot_anno"
        targets$heat_anno <- "heat_anno"
    }

    if (isTRUE(ctx$capabilities$has_cluster)) {
        targets$dot_cluster <- "dot_cluster"
        targets$heat_cluster <- "heat_cluster"
    }

    # 3. Create Cache Folder
    gene_dir <- file.path(ctx$cache, real_gene)
    if (!dir.exists(gene_dir)) dir.create(gene_dir, recursive = TRUE, showWarnings = FALSE)

    # Map for filenames
    suffix_map <- list(
        "feature"      = "feature.png",
        "dot_anno"     = "dot_withanno.png",
        "dot_cluster"  = "dot_noanno.png",
        "heat_anno"    = "heat_withanno.png",
        "heat_cluster" = "heat_noanno.png"
    )

    # 4. Fetch Data Once (Lazy)
    expr_vals <- NULL
    # Helper to get data only if needed
    ensure_data <- function() {
        if (is.null(expr_vals)) {
            expr_vals <<- get_gene_expression(ctx, real_gene)
        }
        return(expr_vals)
    }

    results <- list()

    # 5. Execute Plan
    for (type in names(targets)) {
        filename <- suffix_map[[type]]
        cache_path <- file.path(gene_dir, filename)

        # Check Cache
        if (!file.exists(cache_path) || file.size(cache_path) == 0) {
            # Generate if missing
            vals <- ensure_data()
            if (is.null(vals)) next # Should not happen if check_gene_exists passed

            # Prepare plotting data
            plot_df <- ctx$meta
            if (nrow(plot_df) != length(vals)) {
                flog.error(paste("Data mismatch:", ctx$name))
                next
            }
            plot_df$Expression <- vals

            p <- NULL
            tryCatch(
                {
                    # Plot Generation Logic
                    if (type == "feature") {
                        plot_df <- plot_df[order(plot_df$Expression), ]
                        p <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = Expression)) +
                            geom_point(size = 0.5) +
                            scale_color_gradient(low = "lightgrey", high = "red") +
                            theme_void() +
                            ggtitle(paste(real_gene, "Feature")) +
                            theme(plot.title = element_text(hjust = 0.5))
                    } else if (type == "dot_anno") {
                        if (!"cell_type" %in% names(plot_df)) stop("cell_type missing")
                        stats <- plot_df %>%
                            group_by(cell_type) %>%
                            summarise(AvgExp = mean(exp(Expression) - 1), PctExp = mean(Expression > 0) * 100) %>%
                            mutate(AvgExp = scale(AvgExp))
                        p <- ggplot(stats, aes(x = cell_type, y = 1, size = PctExp, color = AvgExp)) +
                            geom_point() +
                            scale_color_gradient(low = "blue", high = "red") +
                            theme_minimal() +
                            coord_flip() +
                            labs(x = "", y = "", title = paste(real_gene, "DotPlot (Anno)")) +
                            theme(axis.text.x = element_blank())
                    } else if (type == "dot_cluster") {
                        if (!"seurat_clusters" %in% names(plot_df)) stop("seurat_clusters missing")
                        stats <- plot_df %>%
                            group_by(seurat_clusters) %>%
                            summarise(AvgExp = mean(exp(Expression) - 1), PctExp = mean(Expression > 0) * 100) %>%
                            mutate(AvgExp = scale(AvgExp))
                        p <- ggplot(stats, aes(x = as.factor(seurat_clusters), y = 1, size = PctExp, color = AvgExp)) +
                            geom_point() +
                            scale_color_gradient(low = "blue", high = "red") +
                            theme_minimal() +
                            coord_flip() +
                            labs(x = "Cluster", y = "", title = paste(real_gene, "DotPlot (Cluster)")) +
                            theme(axis.text.x = element_blank())
                    } else if (type == "heat_anno") {
                        if (!"cell_type" %in% names(plot_df)) stop("cell_type missing")
                        dat <- plot_df %>%
                            mutate(ScaledExp = pmin(pmax(as.numeric(scale(Expression)), -2.5), 2.5)) %>%
                            arrange(cell_type, Expression) %>%
                            mutate(CellRank = row_number())
                        p <- ggplot(dat, aes(x = CellRank, y = 1, fill = ScaledExp)) +
                            geom_tile() +
                            scale_fill_gradientn(colours = c("#1B7837", "white", "#762A83")) +
                            theme_void() +
                            labs(title = paste(real_gene, "Heatmap (Anno)")) +
                            theme(legend.position = "bottom")
                    } else if (type == "heat_cluster") {
                        if (!"seurat_clusters" %in% names(plot_df)) stop("seurat_clusters missing")
                        dat <- plot_df %>%
                            mutate(ScaledExp = pmin(pmax(as.numeric(scale(Expression)), -2.5), 2.5)) %>%
                            arrange(seurat_clusters, Expression) %>%
                            mutate(CellRank = row_number())
                        p <- ggplot(dat, aes(x = CellRank, y = 1, fill = ScaledExp)) +
                            geom_tile() +
                            scale_fill_gradientn(colours = c("#1B7837", "white", "#762A83")) +
                            theme_void() +
                            labs(title = paste(real_gene, "Heatmap (Cluster)")) +
                            theme(legend.position = "bottom")
                    }

                    # Save
                    if (!is.null(p)) {
                        w <- if (grepl("heat", type)) 10 else 6
                        h <- if (grepl("heat", type)) 3 else if (grepl("dot", type)) 8 else 6
                        ggsave(cache_path, plot = p, width = w, height = h, dpi = 150)
                    }
                },
                error = function(e) {
                    flog.error(paste("Plot failed:", gene, type, e$message))
                }
            )
        }

        # 6. Return Absolute Path
        if (file.exists(cache_path)) {
            # Add to results array (not named list)
            results <- c(results, normalizePath(cache_path))
        }
    }

    return(results)
}

#' Get Base Plots as Absolute Paths (Generate if Missing)
#' @param ctx Dataset context
#' @return List of absolute file paths
get_base_plots_paths <- function(ctx) {
    # Standard base plots from legacy conversion
    # Map friendly name to filename
    # Legacy: uas, ucd45, ucta_withanno, ucta_noanno

    files <- list(
        uas = "uas.png",
        ucd45 = "ucd45.png",
        ucta_withanno = "ucta_withanno.png",
        ucta_noanno = "ucta_noanno.png"
    )

    # Ensure base directory exists
    if (!dir.exists(ctx$base)) {
        dir.create(ctx$base, recursive = TRUE, showWarnings = FALSE)
    }

    results <- list()

    # Helper: Check if generation needed
    missing <- FALSE
    for (name in names(files)) {
        fname <- files[[name]]
        fpath <- file.path(ctx$base, fname)
        if (!file.exists(fpath) || file.size(fpath) == 0) {
            missing <- TRUE
            break
        }
    }

    if (missing) {
        # Generate all base plots if any are missing (keeps it simple)
        plot_df <- ctx$meta

        # 1. UMAP by Sample (uas)
        p1 <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = orig.ident)) +
            geom_point(size = 0.5) +
            theme_void() +
            ggtitle("UMAP: Sample")
        ggsave(file.path(ctx$base, "uas.png"), p1, width = 12, height = 10, dpi = 150)

        # 2. UMAP by CD45 (ucd45)
        if ("CD45_status" %in% names(plot_df)) {
            p2 <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = CD45_status)) +
                geom_point(size = 0.5) +
                scale_color_manual(values = c("red", "blue")) +
                theme_void() +
                ggtitle("UMAP: CD45 Status")
            ggsave(file.path(ctx$base, "ucd45.png"), p2, width = 12, height = 10, dpi = 150)
        }

        # 3. UMAP by Cluster (ucta_noanno)
        if ("seurat_clusters" %in% names(plot_df)) {
            p3 <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = as.factor(seurat_clusters))) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Clusters") +
                guides(color = guide_legend(override.aes = list(size = 4)))
            ggsave(file.path(ctx$base, "ucta_noanno.png"), p3, width = 12, height = 10, dpi = 150)
        }

        # 4. UMAP by CellType (ucta_withanno)
        if ("cell_type" %in% names(plot_df)) {
            p4 <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = cell_type)) +
                geom_point(size = 0.5) +
                theme_void() +
                ggtitle("UMAP: Cell Type") +
                guides(color = guide_legend(override.aes = list(size = 4)))
            ggsave(file.path(ctx$base, "ucta_withanno.png"), p4, width = 12, height = 10, dpi = 150)
        }
    }

    # Collect paths as array
    for (name in names(files)) {
        fname <- files[[name]]
        fpath <- file.path(ctx$base, fname)

        if (file.exists(fpath)) {
            results <- c(results, normalizePath(fpath))
        }
    }
    return(results)
}
