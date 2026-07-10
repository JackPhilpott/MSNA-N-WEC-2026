# ==============================================================================
# Google Open Buildings ingestion
#
# Function:
#   load_building_footprints()
#
# Purpose:
#   Efficiently loads Google Open Buildings File Geodatabases, cleans and
#   filters building footprints, and creates an accessible building polygon
#   sampling frame for Stage 2 household selection.
#
# ==============================================================================


#' Load and preprocess Google Open Buildings footprints
#'
#' Reads Google Open Buildings File Geodatabases, querying each selected
#' Stage-1 sampling cluster individually (rather than loading a whole GDB
#' into memory) so GDAL's spatial index can be used to skip everything
#' outside the clusters. This keeps memory use low even though the source
#' GDBs contain tens of millions of country-wide building footprints -
#' loading a full unfiltered layer this size will exhaust memory on a
#' typical machine.
#'
#' @param gdb_directory Character. Directory containing Google Open Buildings
#'   File Geodatabases.
#' @param accessible_area sf polygon object of the SELECTED Stage-1 sampling
#'   clusters (e.g. \code{bind_rows(host_clusters, idp_clusters)}) - one row
#'   per cluster/hexagon. Buildings are only needed for Stage 2 household
#'   selection within these clusters, not across the whole accessible area,
#'   so passing the full accessible area here would defeat the per-cluster
#'   query strategy and re-introduce the memory problem this function avoids.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param cache_directory Character. Directory for intermediate and final RDS
#'   cache files.
#' @param rebuild Logical. If TRUE, rebuild cached outputs.
#'
#' @return sf polygon object containing cleaned building footprints with:
#' \itemize{
#'   \item building_id
#'   \item confidence
#'   \item building_area_m2
#'   \item geometry
#' }
#'
#' @details
#' Processing workflow, per GDB:
#'
#' \enumerate{
#' \item Identify the building layer and its confidence/area fields.
#' \item For each selected cluster, query the GDB with the cluster's
#'   bounding box (\code{wkt_filter}, spatial-index accelerated) and the
#'   confidence/area thresholds pushed down as a SQL WHERE clause, so only
#'   matching rows are ever pulled into R.
#' \item Combine the per-cluster results, validate geometries, and apply
#'   an exact intersects filter against the true cluster boundaries (the
#'   bounding-box query above is a fast rectangular pre-filter).
#' \item Assign permanent building IDs and cache.
#' }
#'
#' @export
load_building_footprints <- function(
    gdb_directory,
    accessible_area,
    mycrs,
    cache_directory,
    rebuild = FALSE
) {


  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  stopifnot(
    dir.exists(gdb_directory)
  )

  stopifnot(
    inherits(accessible_area, "sf")
  )


  dir.create(
    cache_directory,
    recursive = TRUE,
    showWarnings = FALSE
  )


  final_cache <- file.path(
    cache_directory,
    "accessible_buildings.rds"
  )


  if(file.exists(final_cache) && !rebuild) {

    message("Loading cached: accessible_buildings")

    return(
      readRDS(final_cache)
    )

  }


  # ---------------------------------------------------------------------------
  # CRS preparation
  #
  # Clusters are needed both in WGS84 (to build bounding-box query filters
  # against the source GDBs, which are stored in WGS84) and in the working
  # CRS (for the exact post-query intersects filter).
  # ---------------------------------------------------------------------------

  clusters_proj <- sf::st_transform(
    accessible_area,
    mycrs
  )

  clusters_wgs84 <- sf::st_transform(
    accessible_area,
    4326
  )


  cluster_bbox_wkt <- purrr::map_chr(
    seq_len(nrow(clusters_wgs84)),
    \(i) sf::st_as_text(sf::st_as_sfc(sf::st_bbox(clusters_wgs84[i, ])))
  )


  # ---------------------------------------------------------------------------
  # Locate File Geodatabases
  # ---------------------------------------------------------------------------

  gdb_files <- list.dirs(
    gdb_directory,
    recursive = TRUE,
    full.names = TRUE
  ) |>
    stringr::str_subset("\\.gdb$")


  if(length(gdb_files) == 0) {

    stop(
      "No File Geodatabases found in: ",
      gdb_directory
    )

  }


  message(
    length(gdb_files),
    " Google Open Buildings datasets detected. Querying ",
    nrow(clusters_wgs84),
    " selected clusters against each."
  )


  # ---------------------------------------------------------------------------
  # Fetch buildings for a single cluster from a single GDB
  #
  # wkt_filter is evaluated by GDAL against the layer's spatial index, so
  # even though each GDB has tens of millions of features, a query scoped to
  # one small cluster bounding box returns in a fraction of a second. The
  # confidence/area thresholds are pushed down as a SQL WHERE clause so
  # non-matching rows are never pulled into R at all.
  # ---------------------------------------------------------------------------

  fetch_cluster <- function(
    gdb_path,
    building_layer,
    where_clause,
    confidence_field,
    area_field,
    has_area_field,
    bbox_wkt
  ) {

    result <- tryCatch(
      sf::st_read(
        gdb_path,
        query = paste0(
          'SELECT * FROM "', building_layer, '" WHERE ', where_clause
        ),
        wkt_filter = bbox_wkt,
        quiet = TRUE
      ),
      error = function(e) NULL
    )

    if(is.null(result) || nrow(result) == 0) {
      return(NULL)
    }

    result <- result |>
      dplyr::rename(
        confidence = !!confidence_field
      )

    if(has_area_field) {

      result <- result |>
        dplyr::rename(
          building_area_m2 = !!area_field
        )

    } else {

      result <- result |>
        dplyr::mutate(
          building_area_m2 =
            as.numeric(
              sf::st_area(geometry)
            )
        ) |>
        dplyr::filter(
          building_area_m2 <= 1000,
          building_area_m2 > 0
        )

    }

    result |>
      dplyr::select(
        confidence,
        building_area_m2,
        geometry
      )

  }


  # ---------------------------------------------------------------------------
  # Function to process one GDB across all selected clusters
  # ---------------------------------------------------------------------------

  process_single_gdb <- function(gdb_path) {

    gdb_name <- tools::file_path_sans_ext(
      basename(gdb_path)
    )


    cache_file <- file.path(
      cache_directory,
      paste0(
        gdb_name,
        "_clean.rds"
      )
    )


    if(file.exists(cache_file) && !rebuild) {

      message(
        "Loading cached: ",
        gdb_name
      )

      return(
        readRDS(cache_file)
      )

    }


    message(
      "\nProcessing ",
      gdb_name
    )


    # -------------------------------------------------------------------------
    # Identify building layer
    # -------------------------------------------------------------------------

    layers <- sf::st_layers(
      gdb_path
    )$name


    building_layer <- layers[
      stringr::str_detect(
        tolower(layers),
        "build"
      )
    ]


    if(length(building_layer) == 0) {

      building_layer <- layers[1]

      warning(
        "No building layer detected in ",
        gdb_name,
        ". Using first layer."
      )

    }

    building_layer <- building_layer[1]


    # -------------------------------------------------------------------------
    # Identify confidence/area fields from a single-row sample (avoids
    # reading the full layer just to inspect its schema)
    # -------------------------------------------------------------------------

    sample_row <- sf::st_read(
      gdb_path,
      query = paste0(
        'SELECT * FROM "', building_layer, '" LIMIT 1'
      ),
      quiet = TRUE
    )


    confidence_field <- names(sample_row)[
      stringr::str_detect(
        names(sample_row),
        regex(
          "confidence",
          ignore_case = TRUE
        )
      )
    ][1]


    if(is.na(confidence_field)) {

      stop(
        "Confidence field not found in ",
        gdb_name
      )

    }


    area_field <- names(sample_row)[
      stringr::str_detect(
        names(sample_row),
        regex(
          "^area",
          ignore_case = TRUE
        )
      )
    ]

    has_area_field <- length(area_field) > 0

    area_field <- if(has_area_field) area_field[1] else NA_character_


    # -------------------------------------------------------------------------
    # Attribute filter, pushed down to GDAL rather than applied in R after
    # loading. area_in_meters already exists on the Google Open Buildings
    # source data, so it's reused directly instead of recomputing st_area()
    # over the full geometry set.
    # -------------------------------------------------------------------------

    where_parts <- paste0('"', confidence_field, '" >= 0.75')

    if(has_area_field) {

      where_parts <- c(
        where_parts,
        paste0('"', area_field, '" > 0'),
        paste0('"', area_field, '" <= 1000')
      )

    }

    where_clause <- paste(
      where_parts,
      collapse = " AND "
    )


    # -------------------------------------------------------------------------
    # Query each selected cluster individually
    # -------------------------------------------------------------------------

    buildings <- purrr::map(
      cluster_bbox_wkt,
      \(bbox_wkt) fetch_cluster(
        gdb_path,
        building_layer,
        where_clause,
        confidence_field,
        area_field,
        has_area_field,
        bbox_wkt
      )
    ) |>
      dplyr::bind_rows()


    message(
      gdb_name, ": ",
      nrow(buildings),
      " buildings found across ",
      length(cluster_bbox_wkt),
      " selected clusters"
    )


    if(nrow(buildings) == 0) {

      saveRDS(buildings, cache_file)

      return(buildings)

    }


    # -------------------------------------------------------------------------
    # CRS transformation
    # -------------------------------------------------------------------------

    buildings <- sf::st_transform(
      buildings,
      mycrs
    )


    # -------------------------------------------------------------------------
    # Geometry validation
    # -------------------------------------------------------------------------

    invalid <- !sf::st_is_valid(buildings)

    if (any(invalid)) {
      message(sum(invalid), " invalid geometries detected; repairing...")
      buildings[invalid, ] <- sf::st_make_valid(buildings[invalid, ])
    }


    buildings <- buildings[
      !sf::st_is_empty(buildings),
    ]


    # -------------------------------------------------------------------------
    # Exact cluster boundary filtering
    #
    # The bounding-box query above is a fast rectangular pre-filter; this
    # applies the true cluster/hexagon boundary so buildings just outside a
    # cluster (but inside its bounding box) aren't included. st_filter
    # keeps original building geometries - much faster than st_intersection().
    # -------------------------------------------------------------------------

    buildings <- sf::st_filter(
      buildings,
      clusters_proj,
      .predicate = sf::st_intersects
    )


    message(
      "After exact cluster boundary filter: ",
      nrow(buildings)
    )


    # -------------------------------------------------------------------------
    # Assign permanent building IDs
    # -------------------------------------------------------------------------

    buildings <- buildings |>
      dplyr::mutate(
        building_id =
          paste0(
            gdb_name,
            "_",
            stringr::str_pad(
              dplyr::row_number(),
              width = 10,
              pad = "0"
            )
          )
      )


    # -------------------------------------------------------------------------
    # Save intermediate cache
    # -------------------------------------------------------------------------

    saveRDS(
      buildings,
      cache_file
    )


    buildings

  }


  # ---------------------------------------------------------------------------
  # Process all GDBs
  # ---------------------------------------------------------------------------

  building_parts <- purrr::map(
    gdb_files,
    process_single_gdb
  )


  # ---------------------------------------------------------------------------
  # Combine final building frame
  # ---------------------------------------------------------------------------

  buildings <- dplyr::bind_rows(
    building_parts
  )


  message(
    "\nFinal accessible building frame: ",
    nrow(buildings),
    " buildings."
  )


  # ---------------------------------------------------------------------------
  # Final validation
  # ---------------------------------------------------------------------------

  if(anyDuplicated(buildings$building_id) > 0) {

    stop(
      "Duplicate building IDs detected."
    )

  }


  saveRDS(
    buildings,
    final_cache
  )


  buildings

}
