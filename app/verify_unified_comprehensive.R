# verify_unified_comprehensive.R
library(jsonlite)
library(httr)
library(rhdf5)
library(futile.logger)

CONFIG_PATH <- "config.yaml"
BASE_URL <- "http://localhost:8000"

flog.info("Starting Comprehensive Unified Service Verification...")

if (!file.exists(CONFIG_PATH)) stop("Config not found")
if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml package missing")

cfg <- yaml::yaml.load_file(CONFIG_PATH)
data_root <- cfg$settings$data_path
if (!grepl("^(/|~)", data_root)) {
    data_root <- normalizePath(file.path(getwd(), data_root), mustWork = FALSE)
}

passed_total <- 0
test_total <- 0

# Test 1: Health
resp <- GET(paste0(BASE_URL, "/health"))
if (status_code(resp) == 200) {
    flog.info("[PASS] Service Value Health Check")
    passed_total <- passed_total + 1
} else {
    flog.error("[FAIL] Service Health Check")
}
test_total <- test_total + 1

# List Datasets from Directory
ids <- list.dirs(data_root, full.names = FALSE, recursive = FALSE)
flog.info(paste("Found", length(ids), "datasets for verification."))

# Test 2: Iterate Datasets
for (id in ids) {
    # Construct path based on new standard
    lite_path <- file.path(data_root, id, "lite")
    h5_path <- file.path(lite_path, "expression.h5")

    if (!file.exists(h5_path)) {
        # flog.debug(paste("[SKIP] H5 missing for", id))
        next
    }

    # Pick 2 Random Genes
    tryCatch(
        {
            all_genes <- h5read(h5_path, "genes")
            targets <- sample(all_genes, 2)

            # Add a case variant for the first one
            targets <- c(targets, tolower(targets[1]))

            for (g in targets) {
                test_total <- test_total + 1
                url <- paste0(BASE_URL, "/plots/all?id=", id, "&gene=", g)

                start <- Sys.time()
                r <- GET(url)
                end <- Sys.time()
                dur <- as.numeric(end - start) * 1000

                if (status_code(r) == 200) {
                    # Check Content-Type for image
                    ctype <- headers(r)$`content-type`
                    if (!is.null(ctype) && grepl("image/png", ctype)) {
                        flog.info(sprintf("[PASS] %-5s | %-15s | %4.0fms | Image Received", id, g, dur))
                        passed_total <- passed_total + 1
                    } else {
                        flog.error(sprintf("[FAIL] %-5s | %-15s | Header Mismatch: %s", id, g, toString(ctype)))
                    }
                } else {
                    flog.error(sprintf("[FAIL] %-5s | %-15s | HTTP %d", id, g, status_code(r)))
                }
            }
        },
        error = function(e) {
            flog.error(paste("Error processing", id, ":", e$message))
        }
    )
}

flog.info("==========================================================")
flog.info(sprintf("Summary: %d / %d Tests Passed", passed_total, test_total))
flog.info("==========================================================")

if (passed_total == test_total) {
    quit(status = 0)
} else {
    quit(status = 1)
}
