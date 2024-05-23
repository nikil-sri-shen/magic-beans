(use-trait sip-010-token .traits.ft-trait)
;; (use-trait sip-010-token-lp .traits.ft-trait)

(define-constant err-zero-stx (err u200))
(define-constant err-zero-tokens (err u201))

(define-constant fee-basis-points u30) ;; 0.3%

;; Get contract STX balance
(define-read-only (get-stx-balance)
  (stx-get-balance (as-contract tx-sender))
)

;; Get contract token balance
(define-public (get-token-balance (token <sip-010-token>))
  ;; #[allow(unchecked_data)]
  (contract-call? token get-balance (as-contract tx-sender))
)

;; Provide initial liquidity, defining the initial exchange ratio
(define-private (provide-liquidity-first (token <sip-010-token>) (token-lp <sip-010-token>) (stx-amount uint) (token-amount uint) (provider principal))
    (begin
      ;; send STX from tx-sender to the contract
      (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
      ;; send tokens from tx-sender to the contract
      (try! (contract-call? token transfer token-amount tx-sender (as-contract tx-sender)))
      ;; mint LP tokens to tx-sender
      ;; inside as-contract the tx-sender is the exchange contract, so we use tx-sender passed into the function
      (as-contract (contract-call? .magic-beans-lp mint stx-amount provider))
    )
)

;; Provide additional liquidity, matching the current ratio
;; We don't have a max token amount, that's handled by post-conditions
(define-private (provide-liquidity-additional (token <sip-010-token>) (token-lp <sip-010-token>) (stx-amount uint))
  (let (
      ;; new tokens = additional STX * existing token balance / existing STX balance
      (contract-address (as-contract tx-sender))
      (stx-balance (get-stx-balance))
      (token-balance (unwrap! (get-token-balance token) (err u202)))
      (tokens-to-transfer (/ (* stx-amount token-balance) stx-balance))
      
      ;; new LP tokens = additional STX / existing STX balance * total existing LP tokens
      (liquidity-token-supply (unwrap! (contract-call? token-lp get-total-supply) (err u400)))
      ;; I've reversed the direction a bit here: we need to be careful not to do a division that floors to zero
      ;; additional STX / existing STX balance is likely to!
      ;; Then we end up with zero LP tokens and a sad tx-sender
      (liquidity-to-mint (/ (* stx-amount liquidity-token-supply) stx-balance))

      (provider tx-sender)
    )
    (begin 
      ;; transfer STX from liquidity provider to contract
      (try! (stx-transfer? stx-amount tx-sender contract-address))
      ;; transfer tokens from liquidity provider to contract
      (try! (contract-call? token transfer tokens-to-transfer tx-sender contract-address))
      ;; mint LP tokens to tx-sender
      ;; inside as-contract the tx-sender is the exchange contract, so we use tx-sender passed into the function
      (as-contract (contract-call? .magic-beans-lp mint liquidity-to-mint provider))
    )
  )
)

;; Anyone can provide liquidity by transferring STX and tokens to the contract
(define-public (provide-liquidity (token <sip-010-token>) (token-lp <sip-010-token>) (stx-amount uint) (max-token-amount uint))
  (begin
    (asserts! (> stx-amount u0) err-zero-stx)
    (asserts! (> max-token-amount u0) err-zero-tokens)

    (if (is-eq (get-stx-balance) u0)
      ;; #[allow(unchecked_data)] 
      (provide-liquidity-first token token-lp stx-amount max-token-amount tx-sender)
      ;; #[allow(unchecked_data)]
      (provide-liquidity-additional token token-lp stx-amount)
    )
  )
)

;; Allow users to exchange STX and receive tokens using the constant-product formula
(define-public (stx-to-token-swap (token <sip-010-token>) (stx-amount uint))
  (begin 
    (asserts! (> stx-amount u0) err-zero-stx)
    
    (let (
      (stx-balance (get-stx-balance))
      (token-balance (unwrap! (get-token-balance token) (err u202)))
      ;; constant to maintain = STX * tokens
      (constant (* stx-balance token-balance))
      ;; charge the fee. Fee is in basis points (1 = 0.01%), so divide by 10,000
      (fee (/ (* stx-amount fee-basis-points) u10000))
      (new-stx-balance (+ stx-balance stx-amount))
      ;; constant should = (new STX - fee) * new tokens
      (new-token-balance (/ constant (- new-stx-balance fee)))
      ;; pay the difference between previous and new token balance to user
      (tokens-to-pay (- token-balance new-token-balance))
      ;; put addresses into variables for ease of use
      (user-address tx-sender)
      (contract-address (as-contract tx-sender))
    )
      (begin
        ;; transfer STX from user to contract
        (try! (stx-transfer? stx-amount user-address contract-address))
        ;; transfer tokens from contract to user
        ;; #[allow(unchecked_data)]
        (as-contract (contract-call? token transfer tokens-to-pay contract-address user-address))
      )
    )
  )
)

;; Allow users to exchange tokens and receive STX using the constant-product formula
(define-public (token-to-stx-swap (token <sip-010-token>) (token-amount uint))
  (begin 
    (asserts! (> token-amount u0) err-zero-tokens)
    
    (let (
      (stx-balance (get-stx-balance))
      (token-balance (unwrap! (get-token-balance token) (err u202)))
      ;; constant to maintain = STX * tokens
      (constant (* stx-balance token-balance))
      ;; charge the fee. Fee is in basis points (1 = 0.01%), so divide by 10,000
      (fee (/ (* token-amount fee-basis-points) u10000))
      (new-token-balance (+ token-balance token-amount))
      ;; constant should = new STX * (new tokens - fee)
      (new-stx-balance (/ constant (- new-token-balance fee)))
      ;; pay the difference between previous and new STX balance to user
      (stx-to-pay (- stx-balance new-stx-balance))
      ;; put addresses into variables for ease of use
      (user-address tx-sender)
      (contract-address (as-contract tx-sender))
    )
      (begin
        (print fee)
        (print new-token-balance)
        (print (- new-token-balance fee))
        (print new-stx-balance)
        (print stx-to-pay)
        ;; transfer tokens from user to contract
        ;; #[allow(unchecked_data)]
        (try! (contract-call? token transfer token-amount user-address contract-address))
        ;; transfer tokens from contract to user
        (as-contract (stx-transfer? stx-to-pay contract-address user-address))
      )
    )
  )
)

;; contracts/beanstalk-exchange.clar
;; Anyone can remove liquidity by burning their LP tokens
;; in exchange for receiving their proportion of the STX and token balances
(define-public (remove-liquidity (token <sip-010-token>) (token-lp <sip-010-token>) (liquidity-burned uint))
  (begin
    (asserts! (> liquidity-burned u0) err-zero-tokens)

      (let (
        (stx-balance (get-stx-balance))
        (token-balance (unwrap! (get-token-balance token) (err u202)))
        (liquidity-token-supply (unwrap! (contract-call? token-lp get-total-supply) (err u400)))

        ;; STX withdrawn = liquidity-burned * existing STX balance / total existing LP tokens
        ;; Tokens withdrawn = liquidity-burned * existing token balance / total existing LP tokens
        (stx-withdrawn (/ (* stx-balance liquidity-burned) liquidity-token-supply))
        (tokens-withdrawn (/ (* token-balance liquidity-burned) liquidity-token-supply))

        (contract-address (as-contract tx-sender))
        (burner tx-sender)
      )
      (begin 
        ;; burn liquidity tokens as tx-sender
        (try! (contract-call? .magic-beans-lp burn liquidity-burned))
        ;; transfer STX from contract to tx-sender
        (try! (as-contract (stx-transfer? stx-withdrawn contract-address burner)))
        ;; transfer tokens from contract to tx-sender
        ;; #[allow(unchecked_data)]
        (as-contract (contract-call? token transfer tokens-withdrawn contract-address burner))
      )
    )
  )
)