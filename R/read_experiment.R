#' Read experiment data.
#'
#' Reads a spreadsheet containing a description of all the files required for an
#' experiment to allow batch execution.
#'
#' Information about a full experiment can be assembled into a spreadsheet ( currently
#' Excel and CSV formats are supported) and used to process large numbers of files in one
#' batch. The project directory (\code{project.dir}) is where the arena description files
#' are found. This will typically be the same place as the experiment description file
#' (and is set to be this by default). This does not need to be the same as the current
#' working directory. An optional data directory (\code{data.dir}) can also be specified
#' separately allowing the storage-intensive raw data to be kept in a different location
#' (for example on a remote server). Together, these options allow for flexibility in
#' managing your raw data storage. Individual tracks are associated with their raw data
#' file, experimental group metadata, an arena and any other parameters that the
#' strategy-calling methods require. Required columns are "_TrackID", "_TargetID", "_Day",
#' "_Trial", "_Arena" "_TrackFile" and "_TrackFileFormat" (note the leading underscore
#' "_"). Any additional columns (without a leading underscore) will be interpreted as
#' user-defined factors or other metadata and will be passed on to the final analysis
#' objects and thus be available for statistical analysis.
#'
#' For details on how interpolation is performed (if \code{interpolate} is set to
#' \code{TRUE}), see the documentation for \code{\link{read_path}}.
#'
#' For larger experiments, a computing cluster (using the \code{\link[parallel]{parallel}}
#' package) can be specified, which will be passed to analysis functions and allow the
#' track analysis to be performed in parallel.
#'
#' @param filename A spreadsheet file containing a description of the experiment or a JSON
#'   file containing an exported experiment.
#' @param format An experiment description for reading raw data can be provided as an
#'   Excel spreadsheet ('excel') or as a comma-delimited ('csv') or tab-delimited ('tab',
#'   'tsv', 'txt' or 'text') text file. The value 'json' indicates that the file is an
#'   archived experiment in the JSON format (as generated by \code{\link{export_json}}).
#'   Default (\code{NA}) is to guess the format from the file extension.
#' @param interpolate This is passed to the \code{\link{read_path}} function and specifies
#'   whether missing data points will be interpolated when reading raw swim path data.
#'   Default is \code{FALSE}.
#' @param project.dir A directory path specifying where the files needed for processing
#'   the experiment are stored. Default (\code{NA}) means the project files are in the
#'   same directory as the experiment description (specified by \code{filename}). Ignored
#'   if \code{format = "json"}.
#' @param data.dir A directory path specifying where the raw data are stored. All paths
#'   specified in the experiment description spreadsheet are interpreted as being relative
#'   to the \code{data.dir} directory. Default is the same directory as
#'   \code{project.dir}. Ignored if \code{format = "json"}.
#' @param cluster A cluster object as generated by \code{\link[parallel]{makeCluster}} or
#'   similar.
#' @param author.note Optional text describing the experiment. This might be useful if the
#'   data is to be published or otherwise shared. Appropriate information might be author
#'   names and a link to a publication or website.
#' @param verbose Should feedback be printed to the console. This is only useful for
#'   debugging and takes a little longer to run. Default is \code{FALSE}.
#'
#' @return An \code{rtrack_experiment} object containing a complete description of the
#'   experiment.
#'
#' @seealso \code{\link{read_path}}, \code{\link{read_arena}},
#'   \code{\link{identify_track_format}} to identify the format of your raw track files,
#'   and \code{\link{check_experiment}}.
#'
#' @examples
#' require(Rtrack)
#' experiment.description = system.file("extdata", "Minimal_experiment.xlsx",
#'   package = "Rtrack")
#' experiment = read_experiment(experiment.description)
#'
#' @importFrom readxl read_excel
#' @importFrom utils read.csv read.table
#' @importFrom stats na.omit
#' @importFrom pbapply pblapply pboptions
#' @importFrom parallel clusterExport
#' @importFrom rjson fromJSON
#'
#' @export
read_experiment = function(filename, format = NA, interpolate = FALSE, project.dir = NA, data.dir = project.dir, cluster = NULL, author.note = "", verbose = FALSE){
	if(is.na(project.dir)) project.dir = dirname(filename)
	if(is.na(data.dir)) data.dir = dirname(filename)
	if(unlist(strsplit(project.dir, ""))[nchar(project.dir)] != "/") project.dir = paste0(project.dir, "/")
	if(unlist(strsplit(data.dir, ""))[nchar(data.dir)] != "/") data.dir = paste0(data.dir, "/")
	format = tolower(format)
	if(is.na(format)){
		if(tools::file_ext(filename) %in% c("json")){
			format = "json"
		}else if(tools::file_ext(filename) %in% c("xls", "xlsx")){
			format = "excel"
		}else if(tools::file_ext(filename) %in% c("csv")){
			format = "csv"
		}else if(tools::file_ext(filename) %in% c("tab", "tsv", "txt")){
			format = "tab"
		}else{
			stop("The file format cannot be established. Please specify the 'format' parameter.")
		}
	}
	experiment.data = NULL
	experiment.info = NULL
	
	if(format == "json"){
		experiment.data = rjson::fromJSON(file = filename, simplify = FALSE)
		schema = experiment.data[[1]]
		experiment.info = experiment.data[[2]]
		experiment.data = experiment.data[[3]]
		metrics = NULL
		if(!sum(grepl("cluster", class(cluster)))){
			pbapply::pboptions(type = "timer", txt.width = 50, style = 3, char = "=")
			pb = pbapply::startpb(min = 0, max = length(experiment.data))
			metrics = lapply(1:length(experiment.data), function(i){
				track = experiment.data[[i]]
				this.path = list(
					raw.t = suppressWarnings(as.numeric(unlist(strsplit(track$raw.t, ",")))),
					raw.x = suppressWarnings(as.numeric(unlist(strsplit(track$raw.x, ",")))),
					raw.y = suppressWarnings(as.numeric(unlist(strsplit(track$raw.y, ",")))),
					t = suppressWarnings(as.numeric(unlist(strsplit(track$t, ",")))),
					x = suppressWarnings(as.numeric(unlist(strsplit(track$x, ",")))),
					y = suppressWarnings(as.numeric(unlist(strsplit(track$y, ",")))),
					id = track$id
				)
				class(this.path) = "rtrack_path"
				arena.description = as.data.frame(track$arena, stringsAsFactors = FALSE)
				rownames(arena.description) = "value"
				this.arena = Rtrack::read_arena(NULL, description = arena.description)
				this.metrics = Rtrack::calculate_metrics(this.path, this.arena)
				pbapply::setpb(pb, i)
				return(this.metrics)
			})
			pbapply::closepb(pb)
		}else{
			if(verbose) print(paste0("Processing tracks using ", length(cluster), " cores."))
			pbapply::pboptions(type = "timer", txt.width = 50, style = 3, char = "=")
			metrics = pbapply::pblapply(experiment.data, function(track){
				this.path = list(
					raw.t = suppressWarnings(as.numeric(unlist(strsplit(track$raw.t, ",")))),
					raw.x = suppressWarnings(as.numeric(unlist(strsplit(track$raw.x, ",")))),
					raw.y = suppressWarnings(as.numeric(unlist(strsplit(track$raw.y, ",")))),
					t = suppressWarnings(as.numeric(unlist(strsplit(track$t, ",")))),
					x = suppressWarnings(as.numeric(unlist(strsplit(track$x, ",")))),
					y = suppressWarnings(as.numeric(unlist(strsplit(track$y, ",")))),
					id = track$id
				)
				class(this.path) = "rtrack_path"
				arena.description = as.data.frame(track$arena, stringsAsFactors = FALSE)
				rownames(arena.description) = "value"
				this.arena = Rtrack::read_arena(NULL, description = arena.description)
				this.metrics = Rtrack::calculate_metrics(this.path, this.arena)
				return(this.metrics)
			}, cl = cluster)
		}
		names(metrics) = sapply(metrics, "[[", "id")
		
		# A two-step approach. But this is robust against altered ordering of the factors.
		user.factor.names = unique(do.call("c", lapply(experiment.data, function(track) names(track)[grep("^factor_", names(track))] )))
		user.factors = as.data.frame(do.call("cbind", sapply(user.factor.names, function(n) as.character(sapply(experiment.data, "[[", n)) , simplify = FALSE, USE.NAMES = TRUE)), stringsAsFactors = F)
		factors = data.frame(
			"_TargetID" = sapply(experiment.data, "[[", "target"),
			"_Day" = sapply(experiment.data, "[[", "day"),
			"_Trial" = sapply(experiment.data, "[[", "trial"),
			"_Arena" = sapply(experiment.data, "[[", "arena_name"),
			user.factors,
		stringsAsFactors = FALSE, check.names = FALSE)
		colnames(factors) = gsub("^factor_", "", colnames(factors))
		rownames(factors) = sapply(metrics, "[[", "id")
		experiment = list(metrics = metrics, factors = factors, summary.variables = names(metrics[[1]]$summary), info = experiment.info)
		class(experiment) = "rtrack_experiment"
		return(experiment)
	}
	
	if(format != "json"){
		if(format == "xls" | format == "xlsx" | format == "excel"){
			experiment.data = suppressMessages(as.data.frame(readxl::read_excel(filename, col_types = 'text'), stringsAsFactors = F))
			rownames(experiment.data) = experiment.data$TrackID
		}else if(format == "csv"){
			experiment.data = utils::read.csv(filename, header = TRUE, stringsAsFactors = F, check.names = FALSE)
			rownames(experiment.data) = experiment.data$TrackID
		}else{
			experiment.data = utils::read.table(filename, sep = "\t", header = TRUE, stringsAsFactors = F, check.names = FALSE)
			rownames(experiment.data) = experiment.data$TrackID
		}
		# Run check for required columns
		check = c("_TargetID", "_Day", "_Trial", "_Arena", "_TrackFile", "_TrackFileFormat") %in% colnames(experiment.data)
		if(!all(check)) stop(paste0("The experiment description is missing the required column/s '", paste(c("_TargetID", "_Day", "_Trial", "_Arena", "_TrackFile", "_TrackFileFormat")[!check], collapse = "', '"), "'."))
		if("_TrackIndex" %in% colnames(experiment.data)) experiment.data$`_TrackIndex` = as.numeric(experiment.data$`_TrackIndex`)
		# Extract user columns to a data.frame of factors
		user.columns = sapply(sapply(colnames(experiment.data), strsplit, ""), "[", 1) != "_"
		user.factors = data.frame(experiment.data[, user.columns, drop = FALSE], stringsAsFactors = F)
		factors = data.frame(experiment.data[, c("_TargetID", "_Day", "_Trial", "_Arena")], user.factors, stringsAsFactors = F, check.names = F)
		arenas = sapply(stats::na.omit(unique(experiment.data[, "_Arena"])), simplify = F, USE.NAMES = T, function(arenafile) Rtrack::read_arena(paste0(project.dir, arenafile)) )
		# Calculate metrics for whole experiment (using cluster if available)
		metrics = NULL
		if(!sum(grepl("cluster", class(cluster)))){
			pbapply::pboptions(type = "timer", txt.width = 50, style = 3, char = "=")
			pb = pbapply::startpb(min = 0, max = nrow(experiment.data))
			metrics = lapply(1:nrow(experiment.data), function(i){
				track = experiment.data[i, ]
				this.path = Rtrack::read_path(paste0(data.dir, as.character(track["_TrackFile"])), arenas[[as.character(track["_Arena"])]], id = as.character(track["_TrackID"]), track.format = as.character(track["_TrackFileFormat"]), track.index = experiment.data[i, "_TrackIndex"], interpolate = interpolate)
				pbapply::setpb(pb, i)
				ifelse(length(this.path$t) > 1, {
					this.arena = arenas[[as.character(track["_Arena"])]] # Pre-loaded
					this.metrics = Rtrack::calculate_metrics(this.path, this.arena)
					return(this.metrics)
				}, return(NULL))
			})
			pbapply::closepb(pb)
		}else{
			if(verbose) print(paste0("Processing tracks using ", length(cluster), " cores."))
			pbapply::pboptions(type = "timer", txt.width = 50, style = 3, char = "=")
			parallel::clusterExport(cluster, c("arenas", "data.dir", "experiment.data"), envir = environment()) # Needed for socket clusters
			metrics = pbapply::pblapply(1:nrow(experiment.data), function(i){
				track = experiment.data[i, ]
				this.path = Rtrack::read_path(paste0(data.dir, as.character(track["_TrackFile"])), arenas[[as.character(track["_Arena"])]], id = as.character(track["_TrackID"]), track.format = as.character(track["_TrackFileFormat"]), interpolate = interpolate)
				ifelse(length(this.path$t) > 1, {
					this.arena = arenas[[as.character(track["_Arena"])]] # Pre-loaded
					this.metrics = Rtrack::calculate_metrics(this.path, this.arena)
					return(this.metrics)
				}, return(NULL))
			}, cl = cluster)
		}
		# Resize list to remove any missing data (e.g. from non-existent files)
		keep = !sapply(metrics, is.null)
		metrics = metrics[keep]
		names(metrics) = experiment.data[keep, "_TrackID"]
		factors = factors[keep, ]
		rownames(factors) = experiment.data[keep, "_TrackID"]
		info = list(
			author.note = author.note,
			processing.note = paste0("Experiment processed on ", date(), " by Rtrack (version ", paste0("Rtrack version ", utils::packageVersion("Rtrack")), ") <https://rupertoverall.net/Rtrack>."),
			export.note = ""
		)
		experiment = list(metrics = metrics, factors = factors, summary.variables = names(metrics[[1]]$summary), info = info)
		class(experiment) = "rtrack_experiment"
		return(experiment)
	}
}

