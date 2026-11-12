// Binds the checker into every ucie_ltsm instance; signals connect by name.
bind ucie_ltsm ucie_ltsm_checker #(.TIMEOUT(TIMEOUT)) u_ucie_ltsm_checker (.*);
