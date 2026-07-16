# ==============================================================================
# Google Open Buildings ingestion
#
# Function:
#   load_building_footprints()
#
# Purpose:
#   Efficiently loads Google Open Buildings File Geodatabases, cleans and
#   filters building footprints, converts them to centroid points assigned
#   to their Stage-1 cluster, and returns a lightweight building sampling
#   frame for Stage 2 household selection.
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
#' typical machine. Processing happens in batches, converting each batch to
#' centroid points and assigning them to a cluster before moving to the next
#' batch, since at full survey scale (thousands of clusters) even the
#' deduplicated set of building POLYGONS is too large to hold as one object -
#' points assigned to their cluster are far lighter and let non-matching
#' buildings be dropped immediately instead of carried forward.
#'
#' @param gdb_directory Character. Directory containing Google Open Buildings
#'   File Geodatabases.
#' @param accessible_area sf polygon object of the SELECTED Stage-1 sampling
#'   clusters (e.g. \code{bind_rows(host_clusters, idp_clusters)}), with a
#'   \code{uuid_hex_pop} column identifying the physical hexagon (stable
#'   across repeated PPS draws of the same hexagon) - one row per
#'   cluster/hexagon draw. Buildings are only needed for Stage 2 household
#'   selection within these clusters, not across the whole accessible area,
#'   so passing the full accessible area here would defeat the per-cluster
#'   query strategy and re-introduce the memory problem this function avoids.
#' @param mycrs Coordinate reference system used for spatial processing.
#' @param cache_directory Character. Directory for intermediate and final RDS
#'   cache files.
#' @param min_area_m2 Numeric. Minimum footprint area (square metres) for a
#'   building to be retained. Google Open Buildings frequently detects
#'   individual non-residential structures within a household compound
#'   (kitchen blocks, stores, latrines) as separate footprints; this floor
#'   excludes the smallest of these fragments before Stage 2 household
#'   sampling. It is a light filter, not full compound clustering - some
#'   non-residential picks may still occur and are handled by field
#'   replacement from the Stage 2 reserve list. Default 12.
#' @param rebuild Logical. If TRUE, rebuild cached outputs.
#'
#' @return Character vector of file paths to cached cleaned/cluster-assigned
#'   building points (each an sf POINT RDS with \code{building_id},
#'   \code{confidence}, \code{building_area_m2}, \code{uuid_hex_pop},
#'   \code{geometry}). NOT a single combined object, and not even
#'   necessarily one file per GDB part - a part small enough to combine
#'   internally returns one file; a part too large to combine (this
#'   repeatedly proved to be the actual memory ceiling on this machine,
#'   independent of how the combine was implemented) returns its
#'   \code{flush_threshold}-sized chunk files as-is instead. Google Open
#'   Buildings country-scale tiles also deliberately overlap at their
#'   boundaries, so a cluster's buildings are not guaranteed to be confined
#'   to one file either - \code{select_stage2_households()} determines each
#'   cluster's full file membership up front (pass 1), then accumulates
#'   deduplicated buildings across every file the cluster appears in
#'   (pass 2, deduplicated by rounded centroid) before drawing, rather than
#'   treating any single file as authoritative.
#'
#' @details
#' Processing workflow, per GDB, per batch of clusters:
#'
#' \enumerate{
#' \item Identify the building layer and its confidence/area fields (once
#'   per GDB).
#' \item For each cluster in the batch, query the GDB with the cluster's
#'   bounding box (\code{wkt_filter}, spatial-index accelerated) and the
#'   confidence/area thresholds pushed down as a SQL WHERE clause, so only
#'   matching rows are ever pulled into R.
#' \item Deduplicate against everything seen recently (a rolling window, not
#'   full history - neighbouring clusters' bounding boxes frequently overlap
#'   even though the hexagons themselves do not, so the same building can be
#'   fetched more than once, but clusters far apart in the original sequence
#'   are geographically distant and would never realistically overlap).
#' \item Transform CRS and repair invalid geometries.
#' \item Convert to centroid points, assign permanent building IDs, and
#'   spatially join to the true hexagon boundary (\code{clusters_for_assignment})
#'   - a building whose centroid doesn't fall within any selected hexagon is
#'   dropped here (this is also the exact-boundary filter, replacing the
#'   bounding-box pre-filter's slack).
#' \item Discard the batch's intermediate objects before starting the next
#'   batch, so peak memory is bounded by batch size, not cluster count.
#' \item Flush accumulated results to disk periodically rather than holding
#'   the whole part's result in memory for the part's whole processing
#'   duration, and checkpoint progress after each batch so a killed run
#'   resumes from where it left off instead of restarting.
#' }
#'
#' @export
load_building_footprints <- function(
    gdb_directory,
    accessible_area,
    mycrs,
    cache_directory,
    min_area_m2 = 12,
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
  # Deduplicated cluster polygons (one row per physical hexagon, keyed by
  # uuid_hex_pop) used for per-batch building-to-cluster assignment below.
  # accessible_area can contain multiple rows for the same hexagon (PPS
  # systematic sampling can select the same hex more than once); using the
  # raw un-deduplicated set here would match a building against every one of
  # those repeated rows and produce duplicate output rows for it.
  # uuid_hex_pop (the physical hex identity) is used rather than cluster_id
  # (which is draw-instance-specific) so this stays correct regardless of
  # how downstream code later merges repeated draws into a single cluster.
  # ---------------------------------------------------------------------------

  clusters_for_assignment <-
    clusters_proj %>%
    dplyr::distinct(
      uuid_hex_pop,
      .keep_all = TRUE
    ) %>%
    dplyr::select(
      uuid_hex_pop,
      geometry
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
          building_area_m2 >= min_area_m2
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
        "Already cached (single file): ",
        gdb_name
      )

      return(cache_file)

    }


    chunks_dir <- file.path(cache_directory, paste0(gdb_name, "_chunks"))
    complete_marker <- file.path(cache_directory, paste0(gdb_name, "_complete.marker"))

    if(file.exists(complete_marker) && !rebuild) {

      message(
        "Already cached (chunked): ",
        gdb_name
      )

      return(list.files(chunks_dir, full.names = TRUE))

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
    # over the full geometry set. Lower bound excludes small non-residential
    # fragments (kitchen blocks, stores, latrines) commonly detected as
    # separate footprints within a household compound.
    # -------------------------------------------------------------------------

    where_parts <- paste0('"', confidence_field, '" >= 0.75')

    if(has_area_field) {

      where_parts <- c(
        where_parts,
        paste0('"', area_field, '" >= ', min_area_m2),
        paste0('"', area_field, '" <= 1000')
      )

    }

    where_clause <- paste(
      where_parts,
      collapse = " AND "
    )


    # -------------------------------------------------------------------------
    # Query each selected cluster individually, in batches. Within each
    # batch: deduplicate, validate, convert to centroid POINTS, and assign
    # to a cluster - all before moving to the next batch, so nothing but the
    # lightweight final point result is ever accumulated across batches.
    #
    # Selected hexagons are drawn densely from a shared contiguous grid, so
    # neighbouring clusters' bounding boxes frequently overlap even though
    # the hexagons themselves do not - the same physical building can then
    # be fetched once per overlapping cluster (observed rate: ~72% of rows
    # were duplicates at full 8717-cluster scale). Even after deduplication,
    # holding the full run's buildings as POLYGONS (with their multi-vertex
    # geometries) all the way through to a final combine/spatial-join step
    # is itself too large at this scale (millions of rows across 8717
    # clusters) - it isn't just the raw pre-dedup volume that's the problem.
    # Converting to centroid points and assigning each to its cluster
    # per-batch keeps every accumulated object small: points are far
    # lighter than polygons, and buildings outside every true hexagon
    # (inside the loose bounding-box pre-filter, but not the exact hexagon)
    # are dropped immediately instead of carried forward.
    # -------------------------------------------------------------------------

    # Batch size is deliberately small: cluster density is uneven (a batch
    # covering a dense urban stratum can return orders of magnitude more
    # buildings than a rural one), and the per-batch transform/validate/
    # centroid/join steps below need to stay cheap even for a worst-case
    # dense batch, not just on average.
    batch_size <- 40

    # -------------------------------------------------------------------------
    # Resume support. Cluster density is uneven enough that some stretches
    # of a part are consistently much heavier than others, so a killed run
    # tends to die in the same region on retry - re-processing everything
    # before that region from scratch every attempt wastes real time. A
    # progress file (saved after each completed batch) records everything
    # needed to pick back up: seen_keys (for cross-batch dedup), id_counter
    # (for building_id uniqueness), and how many chunks are already flushed
    # to disk. If present, chunks_dir's existing chunks are kept instead of
    # wiped, and only the remaining batches are processed.
    # -------------------------------------------------------------------------

    progress_file <- file.path(cache_directory, paste0(gdb_name, "_progress.rds"))

    resuming <- file.exists(progress_file)

    if(resuming) {

      progress_state <- readRDS(progress_file)

      seen_keys <- progress_state$seen_keys

      # Trim in case this checkpoint predates the seen_keys windowing fix
      if(length(seen_keys) > 2000000) {
        seen_keys <- seen_keys[(length(seen_keys) - 2000000 + 1):length(seen_keys)]
      }

      id_counter <- progress_state$id_counter
      flush_counter <- progress_state$flush_counter
      total_assigned <- progress_state$total_assigned
      last_completed_batch_end <- progress_state$last_completed_batch_end

      message(
        gdb_name, ": RESUMING from progress file - ",
        total_assigned, " buildings already assigned across ",
        flush_counter, " flushed chunk(s), continuing after cluster ",
        last_completed_batch_end
      )

    } else {

      seen_keys <- character(0)
      id_counter <- 0
      flush_counter <- 0
      total_assigned <- 0
      last_completed_batch_end <- 0

      unlink(chunks_dir, recursive = TRUE)

    }

    dir.create(chunks_dir, recursive = TRUE, showWarnings = FALSE)

    buildings_list <- list()

    batch_starts <- seq(1, length(cluster_bbox_wkt), by = batch_size)
    batch_starts <- batch_starts[batch_starts > last_completed_batch_end]

    # -------------------------------------------------------------------------
    # Even with per-batch and per-row-chunk processing bounded, the ACCUMULATED
    # buildings_list grows across the whole part (millions of rows by the end)
    # and stays resident in memory for the entire loop, which combined with a
    # later dense batch's processing has been enough to exhaust memory on its
    # own. Flushing the accumulator to disk once it crosses flush_threshold
    # rows, and reading the flushed chunks back only once at the very end,
    # keeps in-loop memory bounded regardless of how large the part's total
    # ends up being.
    # -------------------------------------------------------------------------

    # Cluster density varies far more than expected (single 75-cluster
    # batches have ranged from 0 to 370k+ raw rows), so a fixed flush
    # threshold this large still leaves room for a dense batch landing on
    # top of an already-large accumulator to spike memory. A smaller
    # threshold flushes more often but keeps the worst case far smaller.
    flush_threshold <- 75000

    flush_buildings <- function() {

      if(length(buildings_list) == 0) {
        return(invisible(NULL))
      }

      flush_counter <<- flush_counter + 1
      total_assigned <<- total_assigned + sum(purrr::map_int(buildings_list, nrow))

      # Retried with a brief backoff rather than failing outright: unlike
      # the progress checkpoint, this holds actual building data that would
      # otherwise be lost, but the same transient file-lock issue (observed:
      # OneDrive/AV briefly locking a just-written file) can affect this
      # write too.
      to_save <- dplyr::bind_rows(buildings_list)
      chunk_path <- file.path(chunks_dir, paste0("chunk_", flush_counter, ".rds"))

      for(attempt in 1:5) {

        result <- tryCatch({
          saveRDS(to_save, chunk_path)
          TRUE
        }, error = function(e) {
          message("Warning: flush save attempt ", attempt, " failed (", e$message, "), retrying...")
          Sys.sleep(2)
          FALSE
        })

        if(result) break

      }

      buildings_list <<- list()

      gc(full = FALSE)

    }

    save_progress <- function(batch_end) {

      # Written to a temp file and renamed into place rather than saved
      # directly, and wrapped in tryCatch: a transient lock on the target
      # path (observed: OneDrive/AV briefly locking a just-written file)
      # must not crash the whole run over a single skippable checkpoint -
      # worst case, a failed save just means resuming from one batch
      # earlier next time, not losing the run.

      tryCatch({

        tmp_file <- paste0(progress_file, ".tmp")

        saveRDS(
          list(
            seen_keys = seen_keys,
            id_counter = id_counter,
            flush_counter = flush_counter,
            total_assigned = total_assigned,
            last_completed_batch_end = batch_end
          ),
          tmp_file
        )

        file.rename(tmp_file, progress_file)

      }, error = function(e) {

        message("Warning: could not save progress checkpoint (", e$message, ") - continuing.")

      })

    }

    # -------------------------------------------------------------------------
    # Cluster density is uneven enough that even a small (75-cluster) batch
    # can occasionally return several hundred thousand raw rows if it lands
    # on a dense urban stratum. Capping the batch by cluster count alone
    # doesn't bound memory in that case, since the expensive steps
    # (transform/validate/centroid/join) still run on the whole raw fetch
    # at once. row_chunk_size further splits each batch's raw fetch by ROW
    # COUNT before running those steps, so a dense batch's 300k+ rows are
    # processed 25k at a time instead of all at once.
    # -------------------------------------------------------------------------

    row_chunk_size <- 10000
    seen_keys_max <- 2000000

    process_rows <- function(rows) {

      if(nrow(rows) == 0) {
        return(rows)
      }

      # ---- deduplicate (within chunk + against everything seen so far) ----

      cc <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(rows)))
      keys <- paste0(round(cc[, 1], 7), "_", round(cc[, 2], 7))

      keep <- !duplicated(keys) & !(keys %in% seen_keys)

      seen_keys <<- c(seen_keys, keys[keep])

      # Cap to a rolling window rather than unbounded history. seen_keys
      # only needs to catch duplicates from neighbouring clusters' bounding
      # boxes overlapping - clusters far apart in the original sequence are
      # grouped by admin2/stratum and therefore geographically distant, so
      # they'd never realistically produce an overlapping fetch. Unbounded
      # growth here was making every resumed attempt start with a larger
      # baseline memory footprint the further into a part we got, on top of
      # being reloaded in full from the progress checkpoint each time.
      if(length(seen_keys) > seen_keys_max) {
        seen_keys <<- seen_keys[(length(seen_keys) - seen_keys_max + 1):length(seen_keys)]
      }

      rows <- rows[keep, ]

      if(nrow(rows) == 0) {
        return(rows)
      }

      # ---- CRS transform + geometry validation ----

      rows <- sf::st_transform(rows, mycrs)

      invalid <- !sf::st_is_valid(rows)

      if(any(invalid)) {
        rows[invalid, ] <- sf::st_make_valid(rows[invalid, ])
      }

      rows <- rows[!sf::st_is_empty(rows), ]

      if(nrow(rows) == 0) {
        return(rows)
      }

      # ---- centroid conversion + permanent building IDs ----

      n_rows <- nrow(rows)

      rows <- rows %>%
        dplyr::mutate(
          building_id =
            paste0(
              gdb_name, "_",
              stringr::str_pad(id_counter + dplyr::row_number(), width = 10, pad = "0")
            ),
          geometry = sf::st_centroid(geometry)
        ) %>%
        sf::st_as_sf()

      id_counter <<- id_counter + n_rows

      # ---- assign to cluster (also serves as the exact-hexagon filter -
      # ---- a point that doesn't fall within any true hexagon is dropped)

      sf::st_join(
        rows,
        clusters_for_assignment,
        join = sf::st_within,
        left = FALSE
      ) %>%
        dplyr::distinct(building_id, .keep_all = TRUE) %>%
        dplyr::select(
          building_id,
          confidence,
          building_area_m2,
          uuid_hex_pop,
          geometry
        )

    }


    for(batch_start in batch_starts) {

      batch_end <- min(batch_start + batch_size - 1, length(cluster_bbox_wkt))

      batch_buildings <- purrr::map(
        cluster_bbox_wkt[batch_start:batch_end],
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

      gc(full = FALSE)

      n_raw <- nrow(batch_buildings)

      message(
        gdb_name, ": batch ", batch_start, "-", batch_end,
        " raw fetch: ", n_raw, " rows"
      )

      # Flush whatever's already accumulated BEFORE processing a large batch,
      # rather than letting a dense batch land on top of an already-sizeable
      # accumulator - the combination of the two is what has caused crashes
      # even when neither alone would have been a problem.
      if(n_raw > 20000) {

        flush_buildings()

      }

      if(n_raw > 0) {

        row_starts <- seq(1, n_raw, by = row_chunk_size)

        for(row_start in row_starts) {

          row_end <- min(row_start + row_chunk_size - 1, n_raw)

          chunk_result <- process_rows(batch_buildings[row_start:row_end, ])

          if(nrow(chunk_result) > 0) {

            buildings_list[[length(buildings_list) + 1]] <- chunk_result

          }

          rm(chunk_result)
          gc(full = FALSE)

        }

      }

      rm(batch_buildings)
      gc(full = FALSE)

      if(sum(purrr::map_int(buildings_list, nrow)) >= flush_threshold) {

        flush_buildings()

      }

      message(
        gdb_name, ": batch ", batch_start, "-", batch_end,
        " of ", length(cluster_bbox_wkt), " clusters, ",
        length(seen_keys), " unique buildings seen, ",
        total_assigned + sum(purrr::map_int(buildings_list, nrow)),
        " assigned to a cluster so far (", flush_counter, " chunk(s) flushed to disk)"
      )

      save_progress(batch_end)

    }

    flush_buildings()

    rm(seen_keys)
    gc(full = FALSE)

    # No final combine into one cache_file. Even reading the chunk files
    # back incrementally (one at a time, discarding each after folding it
    # into a running total) still repeatedly failed to complete for the
    # largest part (~8.4M rows) - the final assembled object's own size,
    # not how it was built, was the actual ceiling. The chunk files
    # (already bounded in size by flush_threshold) are left in place
    # permanently instead and returned as-is; select_stage2_households()
    # processes each one separately, the same way it processes each GDB
    # part, so nothing downstream ever needs this part combined into a
    # single object either.
    chunk_files <- list.files(chunks_dir, full.names = TRUE)

    file.create(complete_marker)
    unlink(progress_file)

    message(
      gdb_name, ": done - ",
      length(chunk_files), " chunk file(s) covering ",
      length(cluster_bbox_wkt), " selected clusters (kept separate, not combined)"
    )

    chunk_files

  }


  # ---------------------------------------------------------------------------
  # Process all GDBs. purrr::walk() (not map()) - process_single_gdb() caches
  # its own result to disk internally, so its return value is discarded here
  # rather than accumulated across all 3 parts in memory. Accumulating each
  # completed part's full result (millions of rows) while processing the
  # next part was itself enough to exhaust memory - the same "accumulate
  # instead of flush" problem as within a single part, one level up.
  # ---------------------------------------------------------------------------

  # process_single_gdb() returns file paths only (a single cache_file path,
  # or a vector of chunk file paths) - purrr::map() (not walk()) to collect
  # them is fine here since these are lightweight path lists, not data.
  part_cache_files <- purrr::map(
    gdb_files,
    process_single_gdb
  ) %>%
    unlist()

  gc(full = FALSE)


  # ---------------------------------------------------------------------------
  # Return every cache/chunk file path rather than one combined object.
  #
  # At full survey scale the 3 parts together are 13M+ building points -
  # materializing that as a single in-memory sf object (however it's
  # assembled, and even per-part rather than across all 3) repeatedly
  # proved to be the actual memory ceiling on this machine. Google Open
  # Buildings country-scale tiles deliberately overlap at their boundaries
  # (confirmed empirically - a hexagon can have buildings appear in more
  # than one part's file), so select_stage2_households() cannot assume a
  # cluster's buildings come from exactly one file; it instead determines
  # each cluster's full file membership first, then accumulates
  # deduplicated buildings across all of them before drawing, which
  # resolves the boundary overlap without ever needing to combine files
  # together.
  # ---------------------------------------------------------------------------

  stopifnot(
    "Not all GDB parts were successfully cached" = length(part_cache_files) > 0 && all(file.exists(part_cache_files))
  )

  part_cache_files

}
