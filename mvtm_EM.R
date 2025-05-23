library(mvtnorm) # want to use this for multivariate t-dist pdf but may swap to custom function

# Multivariate t-Distribution PDF: May be used later

dmvt_custom <- function(y, mu, sigma, nu){
  p <- length(y)
  sig_inv <- chol2inv(chol(sigma))
  sig_det <- 1/prod(diag(chol(sigma)))
  delta <- as.numeric(t(y - mu) %*% sig_inv %*% (y - mu))
  C <- (gamma((nu+p)/2) * sig_det) / (pi * nu)^(p/2) / gamma(nu/2) / (1+delta/nu)^((nu+p)/2)
  return(C)
}

# E-Step Functions

compute_tau <- function(data, pi, mu, sigma, nu) {
  
  n <- nrow(data)
  g <- length(pi)
  if(nrow(mu) != g || dim(sigma)[3] != g || length(nu) != g) {
    stop('dimensions are wrong')
  }
  
  tau <- matrix(0, nrow = n, ncol = g)
  
  for (j in 1:g) {
    tau[, j] <- pi[j] * dmvt(x = data, delta = mu[j, ], sigma = sigma[, , j], df = nu[j], log = FALSE)
  }
  
  return(tau / rowSums(tau, na.rm = T))
}

compute_u <- function(data, mu, sigma, nu) {
  g <- nrow(mu)
  p <- ncol(mu)
  n <- nrow(data)
  
  sigma_inv <- array(0, dim = dim(sigma))
  for(i in 1:g) {
    sigma_inv[,,i] <- chol2inv(chol(sigma[,,i]))
  }
  
  u <- matrix(0, nrow = n, ncol = g)
  
  top <- nu + p
  
  for (j in 1:g) {
    centered <- t(t(data) - mu[j,])
    delta <- rowSums((centered %*% sigma_inv[,,j]) * centered)
    u[,j] <- top[j] / (nu[j] + delta)
  }
  
  return(u)
}

# M-Step Functions

update_pi <- function(tau) colMeans(tau, na.rm = T)

update_mu <- function(data, tau, u){
  w <- tau * u
  return(t(w) %*% data / colSums(w, na.rm = T))
}

update_sigma <- function(data, mu, tau, u){
  g <- ncol(tau)
  p <- ncol(data)
  sigma <- array(0, dim = c(p,p,g))
  
  for(i in 1:g){
    w <- sqrt(tau[,i] * u[,1])
    centered <- (data - mu[rep(i, nrow(data)),]) * w
    sigma[,,i] <- crossprod(centered) / sum(tau[,i])
  }
  
  return(sigma)
}

update_nu <- function(tau, u, nu, p, tol = 1e-6, maxiter = 1000) {
  g <- ncol(tau)
  nu_new <- numeric(g)
  n_i <- colSums(tau)
  
  for (i in 1:g) {
    constant_term <- sum(tau[, i] * (log(u[, i]) - u[, i])) / n_i[i] + digamma((nu[i] + p)/2) - log((nu[i] + p)/2)
    
    root_eq <- function(nu0) -digamma(nu0/2) + log(nu0/2) + 1 + constant_term
    nu_new[i] <- uniroot(root_eq, interval = c(1e-6, 1e6), tol = tol, maxiter = maxiter)$root
  }
  
  return(nu_new)
}

# EM Algorithm for Multivariate t-Distribution Mixture

mvtm_EM <- function(data, g, max_iter = 1000, tol = 1e-6, progress = T){
  
  # Initialize Parameters
  
  n <- nrow(data)
  p <- ncol(data)
  loglik <- numeric(max_iter)
  converged <- F
  start_time <- Sys.time()
  
  pi <- rep(1/g, g)
  mu <- data[sample(n,g), , drop = F]
  sigma <- array(diag(p), dim = c(p,p,g))
  nu <- rep(30, g)
  
  for(iter in 1:max_iter){
    
    # E-Step
    
    tau <- compute_tau(data, pi, mu, sigma, nu)
    u <- compute_u(data, mu, sigma, nu)
    
    # M-Step
    
    pi_new <- update_pi(tau)
    mu_new <- update_mu(data, tau, u)
    sigma_new <- update_sigma(data, mu_new, tau, u)
    nu_new <- update_nu(tau, u, nu, p)
    
    # Convergence Check
    
    log_dens <- matrix(0, nrow = n, ncol = g)
    for (j in 1:g) {
      log_dens[, j] <- log(pi_new[j]) + dmvt(data, delta = mu_new[j,], sigma = sigma_new[,,j], df = nu_new[j], log = TRUE)
    }
    
    max_log <- apply(log_dens, 1, max)
    loglik[iter] <- sum(max_log + log(rowSums(exp(log_dens - max_log))))
    
    if(iter > 1) {
      delta <- abs(loglik[iter] - loglik[iter - 1]) / max(abs(loglik[iter-1]), 1e-6)
      if(is.na(delta) || delta < tol) {
        converged <- !is.na(delta)
        break
      }
    }
    
    # Update Parameters
    
    pi <- pi_new
    mu <- mu_new
    sigma <- sigma_new
    nu <- nu_new
    
    # Progress Output
    
    if (progress && (iter %% 10 == 0 || iter == 1 || iter == max_iter || converged)) {
      runtime <- difftime(Sys.time(), start_time, units = "secs")
      cat(sprintf("Iteration %4d: log-likelihood = %12.4f | Time: %6.1fs\n", 
                  iter, loglik[iter],
                  as.numeric(runtime)))
    }
    
  }
  
  # Output Stuff
  
  return(
    list(
      pi = pi,
      mu = mu,
      sigma = sigma,
      nu = nu,
      tau = tau,
      loglik = loglik[1:iter],
      converged = converged,
      iterations = iter
    )
  )
}


### Simulation Function Generated by Deepseek :)

generate_tmixture_data <- function(n, mu, sigma, nu , shuffle = TRUE){
  
  g <- length(n)  # Number of components
  p <- length(mu[[1]])  # Dimension
  
  # Validate inputs
  stopifnot(length(mu) == g,
            length(sigma) == g,
            length(nu) == g,
            all(sapply(mu, length) == p),
            all(sapply(sigma, function(s) all(dim(s) == c(p, p)))))
  
  # Generate data for each component
  data_list <- lapply(1:g, function(i) {
    rmvt(n[i], sigma = sigma[[i]], delta = mu[[i]], df = nu[i])
  })
  
  # Combine and shuffle if requested
  true_clusters <- rep(1:g, times = n)
  data <- do.call(rbind, data_list)
  
  if (shuffle) {
    shuffle_idx <- sample(nrow(data))
    data <- data[shuffle_idx, ]
    true_clusters <- true_clusters[shuffle_idx]
  }
  
  # Return results with true parameters
  list(
    data = data,
    true_clusters = true_clusters,
    true_params = list(
      pi = n/sum(n),
      mu = do.call(rbind, mu),
      sigma = simplify2array(sigma),
      nu = nu
    )
  )
}

# sim_data <- generate_tmixture_data(
#   n = c(300, 400, 500),
#   mu = list(c(0, 0), c(4, 4), c(-4, 4)),
#   sigma = list(
#     diag(c(1, 1)),
#     matrix(c(2, 1.5, 1.5, 2), 2),
#     matrix(c(1, -0.7, -0.7, 1), 2)
#   ),
#   nu = c(3, 15, 50)
# )
# 
# fit <- mvtm_EM(
#   data = sim_data$data,
#   g = 3,
#   tol = 1e-9,
#   progress = TRUE
# )
# 
# pred_clusters <- apply(fit$tau, 1, which.max)
# 
# par(mfrow = c(1, 2))
# plot(sim_data$data, col = sim_data$true_clusters, pch = 20,
#      main = 'True Clusters', xlab = '', ylab = '')
# plot(sim_data$data, col = pred_clusters, pch = 20,
#      main = 'Estimated Clusters', xlab = '', ylab = '')


