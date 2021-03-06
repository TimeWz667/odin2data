#' @rdname compile_model
#' @export
test_model <- function(d_prior, r_prior, y0, inp_sim = NULL, ts_sim, m_sim, r_sto_sim,
                       inp_wp = NULL, t_wp, m_wp, r_sto_wp, fn_pass_y0, fn_check, method) {
  res <- list()

  fp <- r_prior()
  res$FreeParameters <- fp

  stopifnot(is.finite(d_prior(fp)))

  res$d_prior <- d_prior
  res$r_prior <- r_prior

  if (is.null(method)) method = "rk4"

  if (missing(r_sto_sim)) {
    r_sto_sim <- function(pars, inp=NULL) {
      NULL
    }
  }

  if (missing(r_sto_wp)) {
    r_sto_wp <- function(pars, inp=NULL) {
      NULL
    }
  }

  if (missing(t_wp) | missing(m_wp) | missing(fn_pass_y0)) {
    res$WarmupStage <- "No"
  } else {
    res$WarmupStage <- "Yes"

    pars <- fp
    if (missing(inp_wp) | any(is.null(inp_wp))) {
      inp_wp <- NULL
    }

    sto <- r_sto_wp(pars, inp_wp)
    pars <- c(pars, sto, inp_wp)

    pars$Y0 <- y0

    cm_wp <- m_wp(user = pars)
    ts_wp <- ts_sim[1] - (t_wp:0)

    st <- system.time({ ys0 <- cm_wp$run(ts_wp, method = method) })
    cat("Warm-up time:\n")
    print(st)

    ys0 <- ys0[ts_wp == round(ts_wp), ]

    if (is.array(y0)) {
      dim0 <- dim(y0)
      y0new <- array(ys0[nrow(ys0), 1 + 1:prod(dim0)], dim0)
    } else if (is.vector(y0)) {
      y0new <- ys0[nrow(ys0), 1 + 1:length(y0)]
    }

    res <- c(res, list(
      Input_wp = inp_wp,
      dimY0_wp = dim(y0),
      Y0_wp = y0new,
      Ys_wp = ys0,
      CM_wp = cm_wp,
      r_sto_wp = r_sto_wp,
      Time_wp = range(ts_wp),
      TS_wp = ts_wp
    ))

    if(!missing(fn_check)) {
      stopifnot(fn_check(ys0))
      res$Checker <- fn_check
    }
    y0 <- fn_pass_y0(ys0)
    res$Linker = fn_pass_y0
  }

  pars <- fp

  if (missing(inp_sim) | any(is.null(inp_sim))) {
    inp_sim <- NULL
  }
  if (res$WarmupStage == "No" | !identical(r_sto_sim, r_sto_wp)) {
    sto <- r_sto_sim(pars, inp_sim)
  }
  pars <- c(pars, sto, inp_sim)

  pars$Y0 <- y0

  cm_sim <- m_sim(user = pars)

  st <- system.time({ ys1 <- cm_sim$run(ts_sim, method = method) })
  cat("Simulation time:\n")
  print(st)

  ys1 <- ys1[ts_sim == round(ts_sim),]

  res <- c(res, list(
    Input_sim = inp_sim,
    Y0_sim = y0,
    Ys_sim = ys1,
    CM_sim = cm_sim,
    r_sto_sim = r_sto_sim,
    Time_sim = range(ts_sim),
    TS_sim = ts_sim,
    Method = method
  ))
  return(res)
}


#' Compile a simulation model given all components
#'
#' @param d_prior a probability density function supporting prior distributions
#' @param r_prior a function for generating parameters from their prior distributions
#' @param y0 initial values
#' @param inp_sim input data for the simulation stage
#' @param ts_sim timespan for simulation
#' @param m_sim an odin model for simulation
#' @param r_sto_sim a function of (prior, input) for generating internal stochasticity or modifying input
#' @param inp_wp input data for the warm-up stage
#' @param t_wp length of warm-up stage
#' @param m_wp an odin model for warm-up
#' @param r_sto_wp a function of (prior, input) for generating internal stochasticity or modifying input for the warm-up stage
#' @param fn_pass_y0 a function for bringing the states at the end of warm-up to simulation initials
#' @param fn_check a function for checking if a parameter set can generate validated output
#'
#' @return
#' @export
#'
#' @examples
compile_model <- function(d_prior, r_prior, y0,
                          inp_sim = NULL, ts_sim, m_sim, r_sto_sim,
                          inp_wp = NULL, t_wp, m_wp = m_sim, r_sto_wp = NULL,
                          fn_pass_y0, fn_check, method = NULL, max_attempt = 10) {
  n_attempt <- 0

  if (missing(fn_check)) {
    fn_check <- function(x) { T }
  }

  while(T) {
    tested <- tryCatch({
      test_model(d_prior, r_prior, y0, inp_sim, ts_sim, m_sim, r_sto_sim,
                 inp_wp, t_wp, m_wp, r_sto_wp, fn_pass_y0, fn_check, method)
    }, error = function(e) e$message)


    n_attempt <- n_attempt + 1
    if (is.list(tested)) break

    stopifnot(n_attempt < max_attempt)
  }
  class(tested) <- "sim_model"
  return(tested)
}


#' Compile a simulation model with a likelihood-free link to data
#'
#' @param dat a dataframe of data to be fitted, "t" as the indicator of time
#' @param sim a compile model, see compile_model
#'
#' @return a compiled model with data
#' @export
compile_model_likefree <- function(dat, sim) {

  vars <- intersect(colnames(sim$Ys_sim), colnames(dat))
  vars <- vars[vars != "t"]

  res <- list(
    Data = dat,
    Model = sim,
    Cols2fit = vars,
    Ts2fit = dat[, "t"]
  )

  class(res) <- "sim_model_likefree"
  return(res)
}


#' Compile a simulation model with a likelihood function to data
#'
#' @param sim a compile model, see compile_model
#' @param fn_like likelihood function
#'
#' @return a compiled model with likelihood function
#' @export
compile_model_likelihood <- function(fn_like, sim) {

  res <- list(
    Model = sim,
    FnLike = fn_like
  )

  class(res) <- "sim_model_likelihood"
  return(res)
}
