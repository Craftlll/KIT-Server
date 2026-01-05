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

#* Get Gene Expression Plot
#* @param id The Dataset ID
#* @param gene The Gene Name
#* @param type Plot type (feature, dot_anno, dot_cluster, heat_anno, heat_cluster). Default: feature
#* @serializer contentType list(type="image/png")
#* @get /plots/all
function(id, gene, type = "feature", res) {
    ctx <- get_dataset_context(id)
    if (is.null(ctx)) {
        res$status <- 404
        return(list(error = "Dataset ID not found"))
    }

    # Generate Plot
    # The utils_plot function now handles 'type'
    plot_path <- generate_plot(ctx, gene, plot_type = type)

    if (!is.null(plot_path) && file.exists(plot_path)) {
        return(readBin(plot_path, "raw", n = file.info(plot_path)$size))
    } else {
        res$status <- 440
        return(list(error = paste("Gene", gene, "not found or plot generation failed for type", type)))
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
