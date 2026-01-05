# R/utils_plot.R
library(ggplot2)

#' Generate and Cache Plot
#' @param ctx Dataset context from get_dataset_context()
#' @param gene Gene name
#' @return Path to the generated PNG
#' Generate and Cache Plot
#' @param ctx Dataset context
#' @param gene Gene name
#' @param plot_type Type of plot: feature, dot_anno, dot_cluster, heat_anno, heat_cluster
#' @return Path to the generated PNG
generate_plot <- function(ctx, gene, plot_type = "feature") {
    # 1. Resolve Gene
    real_gene <- check_gene_exists(ctx, gene)
    if (is.null(real_gene)) {
        return(NULL)
    }

    # 2. Define Cache Path
    # Map API type to filename suffix
    suffix_map <- list(
        "feature"      = "feature.png",
        "dot_anno"     = "dot_anno.png",
        "dot_cluster"  = "dot_cluster.png",
        "heat_anno"    = "heat_anno.png",
        "heat_cluster" = "heat_cluster.png"
    )

    if (!plot_type %in% names(suffix_map)) {
        flog.warn(paste("Unknown plot type:", plot_type))
        return(NULL)
    }

    # Cache structure: {cache_dir}/{Gene}/{type}.png
    # Creating a subfolder per gene keeps the main cache dir clean
    gene_dir <- file.path(ctx$cache, real_gene)
    if (!dir.exists(gene_dir)) dir.create(gene_dir, recursive = TRUE, showWarnings = FALSE)

    filename <- suffix_map[[plot_type]]
    cache_path <- file.path(gene_dir, filename)

    if (file.exists(cache_path) && file.size(cache_path) > 0) {
        return(cache_path)
    }

    # 3. Fetch Data (Lazy Loading)
    expr_vals <- get_gene_expression(ctx, real_gene)
    if (is.null(expr_vals)) {
        return(NULL)
    }

    plot_df <- ctx$meta
    # Safety Check
    if (nrow(plot_df) != length(expr_vals)) {
        return(NULL)
    }

    plot_df$Expression <- expr_vals

    # 4. Generate Specific Plot
    p <- NULL

    # Common theme setup
    library(ggplot2)
    library(dplyr)

    tryCatch(
        {
            if (plot_type == "feature") {
                # Standard Feature Plot
                plot_df <- plot_df[order(plot_df$Expression), ]
                p <- ggplot(plot_df, aes(x = UMAP_1, y = UMAP_2, color = Expression)) +
                    geom_point(size = 0.5) +
                    scale_color_gradient(low = "lightgrey", high = "red") +
                    theme_void() +
                    ggtitle(paste(real_gene, "Feature")) +
                    theme(plot.title = element_text(hjust = 0.5))
            } else if (plot_type == "dot_anno") {
                # DotPlot by Cell Type
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
            } else if (plot_type == "dot_cluster") {
                # DotPlot by Cluster
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
            } else if (plot_type == "heat_anno") {
                # Heatmap by Cell Type
                if (!"cell_type" %in% names(plot_df)) stop("cell_type missing")
                # Downsample for heatmap performance if needed, but for 'lite' full might be okay or use aggregate?
                # Legacy script plots all cells.
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
            } else if (plot_type == "heat_cluster") {
                # Heatmap by Cluster
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
                # Dimensions varying by type
                w <- if (grepl("heat", plot_type)) 10 else 6
                h <- if (grepl("heat", plot_type)) 3 else if (grepl("dot", plot_type)) 8 else 6

                ggsave(cache_path, plot = p, width = w, height = h, dpi = 150)
                return(cache_path)
            }
        },
        error = function(e) {
            flog.error(paste("Plot gen failed for", gene, plot_type, ":", e$message))
            return(NULL)
        }
    )

    return(NULL)
}
