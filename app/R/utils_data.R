# R/utils_data.R
library(jsonlite)
library(rhdf5)
library(futile.logger)

# Global Registry
DATA_REGISTRY <- list()

#' Initialize the registry from config.yaml
init_registry <- function(config_path = "config.yaml") {
    if (!file.exists(config_path)) stop("Config not found")

    # Load YAML
    if (!requireNamespace("yaml", quietly = TRUE)) {
        stop("Package 'yaml' is required. Please install it.")
    }
    cfg <- yaml::yaml.load_file(config_path)

    # Resolve Data Path
    data_root <- cfg$settings$data_path
    # If path is relative (doesn't start with / or ~), prepend current WD
    if (!grepl("^(/|~)", data_root)) {
        data_root <- normalizePath(file.path(getwd(), data_root), mustWork = FALSE)
    }

    flog.info(paste("Initializing Data Registry from root:", data_root))

    if (!dir.exists(data_root)) {
        flog.error(paste("Data directory not found:", data_root))
        return()
    }

    # Scan for potential datasets (dirs in root)
    candidates <- list.dirs(data_root, full.names = FALSE, recursive = FALSE)

    for (id in candidates) {
        # Define structure: {ROOT}/{ID}/lite/{files}
        lite_path <- file.path(data_root, id, "lite")

        meta_file <- file.path(lite_path, "metadata.csv")
        h5_file <- file.path(lite_path, "expression.h5")
        cache_dir <- file.path(lite_path, "cache")
        base_dir <- file.path(lite_path, "base")

        if (file.exists(meta_file) && file.exists(h5_file)) {
            # Load metadata
            meta_df <- tryCatch(
                {
                    read.csv(meta_file, row.names = NULL)
                },
                error = function(e) {
                    flog.error(paste("Failed to read metadata for", id, ":", e$message))
                    NULL
                }
            )

            if (!is.null(meta_df)) {
                # Ensure cache dir exists
                if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

                DATA_REGISTRY[[id]] <<- list(
                    name = paste("Dataset", id), # Default name
                    meta = meta_df,
                    h5 = h5_file,
                    cache = cache_dir,
                    base = base_dir
                )
                flog.info(paste("Loaded:", id, "| Rows:", nrow(meta_df)))
            }
        } else {
            # Silent skip for non-dataset directories to avoid log spam
            # flog.debug(paste("Skipping:", id))
        }
    }
    flog.info(paste("Registry initialized with", length(DATA_REGISTRY), "datasets."))
}

#' Get context for a specific dataset ID
get_dataset_context <- function(id) {
    if (is.null(DATA_REGISTRY[[id]])) {
        return(NULL)
    }
    return(DATA_REGISTRY[[id]])
}

#' Check if gene exists in HDF5
check_gene_exists <- function(ctx, gene) {
    # H5 structure: /genes (dataset)
    # Optimized: Read only if not cached?
    # For now, read the 'genes' vector. Since it's small, we could cache it in memory too,
    # but let's read from disk for simplicity or cache in ctx if needed.
    # PROD OPTIMIZATION: Cache gene list in memory at init?
    # Let's do a quick read.

    # Try case-insensitive match
    all_genes <- tryCatch(h5read(ctx$h5, "genes"), error = function(e) NULL)
    if (is.null(all_genes)) {
        return(NULL)
    }

    # Exact match
    if (gene %in% all_genes) {
        return(gene)
    }

    # Case insensitive
    idx <- match(tolower(gene), tolower(all_genes))
    if (!is.na(idx)) {
        return(all_genes[idx])
    }

    return(NULL)
}

#' Fetch expression data for a gene
get_gene_expression <- function(ctx, gene) {
    real_gene <- check_gene_exists(ctx, gene)
    if (is.null(real_gene)) {
        return(NULL)
    }

    # Find index
    all_genes <- h5read(ctx$h5, "genes")
    gene_idx <- match(real_gene, all_genes)

    # Read column (gene_idx)
    # matrix is genes x cells
    expr <- h5read(ctx$h5, "expression", index = list(gene_idx, NULL))
    return(as.vector(expr))
}
