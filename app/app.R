# app.R
library(plumber)
library(futile.logger)

# Load Utilities
source("R/utils_data.R")
source("R/utils_plot.R")

# Initialize Registry (Load Metadata)
# Uses config.yaml by default now
init_registry("config.yaml")

#* @apiTitle Unified Single-Cell Lite Service
#* @apiDescription Serves plots for multiple datasets via a unified interface.

#* Log Requests
#* @filter logger
function(req) {
    flog.info(paste(
        req$method, req$path,
        "| ID:", toString(req$args$id),
        "| Gene:", toString(req$args$gene)
    ))
    plumber::forward()
}

#* Check Health
#* @get /health
function() {
    list(status = "UP", mode = "Unified")
}

#* List available datasets
#* @get /datasets
function() {
    ids <- names(DATA_REGISTRY)
    out <- lapply(ids, function(i) list(id = i, name = DATA_REGISTRY[[i]]$name))
    list(datasets = out)
}

#* Check if a gene exists in a dataset
#* @param id The Dataset ID (e.g. NO1)
#* @param gene The Gene Name
#* @get /genes/check
function(id, gene, res) {
    ctx <- get_dataset_context(id)
    if (is.null(ctx)) {
        res$status <- 404
        return(list(error = "Dataset ID not found"))
    }

    real_name <- check_gene_exists(ctx, gene)
    if (!is.null(real_name)) {
        res$status <- 200 # Found
        return(list(found = TRUE, gene = real_name))
    } else {
        res$status <- 440 # Application standard for "Gene Not Found"
        return(list(error = paste("Gene", gene, "not found")))
    }
}

#* Get Base UMAP Plot
#* @param id The Dataset ID
#* @serializer contentType list(type="image/png")
#* @get /plots/base
function(id, res) {
    ctx <- get_dataset_context(id)
    if (is.null(ctx)) {
        res$status <- 404
        return(list(error = "Dataset ID not found"))
    }

    # Return pre-generated base plot
    # Assuming standard name 'uas.png' or similar from conversion
    # Let's verify what the conversion script names them. Usually 'uas.png' or 'no_legend.png'
    # Based on previous scripts: 'uas.png'
    base_plot <- file.path(ctx$base, "uas.png")

    if (file.exists(base_plot)) {
        return(readBin(base_plot, "raw", n = file.info(base_plot)$size))
    } else {
        res$status <- 404
        return(list(error = "Base plot not pre-generated"))
    }
}

#* Get Gene Expression Plots (Batch)
#* @param id The Dataset ID
#* @param gene The Gene Name
#* @serializer json
#* @get /plots/all
function(id, gene, res) {
    ctx <- get_dataset_context(id)
    if (is.null(ctx)) {
        res$status <- 404
        return(list(error = "Dataset ID not found"))
    }

    # Helper: Check if gene exists first
    real_gene <- check_gene_exists(ctx, gene)
    if (is.null(real_gene)) {
        res$status <- 440
        return(list(error = paste("Gene", gene, "not found")))
    }

    # Batch Generate & Return Paths
    # This automatically handles capability detection (anno/cluster/etc.)
    gene_plots <- process_gene_plots(ctx, gene)
    base_plots <- get_base_plots_paths(ctx)

    if (!is.null(gene_plots) && length(gene_plots) > 0) {
        # Return list of absolute file paths
        # Structure: { gene: "...", plots: { ... }, base_plots: { ... } }
        return(list(
            gene = real_gene,
            plots = gene_plots,
            base_plots = base_plots
        ))
    } else {
        res$status <- 500
        return(list(error = "Plot generation failed"))
    }
}

#* Get Available Plot Types
#* @param id The Dataset ID
#* @get /plots/types
function(id, res) {
    ctx <- get_dataset_context(id)
    if (is.null(ctx)) {
        res$status <- 404
        return(list(error = "Dataset ID not found"))
    }

    # Check what columns exist in metadata
    cols <- names(ctx$meta)

    types <- c("feature")
    if ("cell_type" %in% cols) types <- c(types, "dot_anno", "heat_anno")
    if ("seurat_clusters" %in% cols) types <- c(types, "dot_cluster", "heat_cluster")

    list(types = types)
}

#* Serve Static Files (Utils)
#* @assets /Users/craft/Desktop/KIT/env/dataset /static
list()
