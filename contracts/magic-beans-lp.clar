;; contracts/magic-beans-lp.clar
(impl-trait .traits.ft-trait)
(define-fungible-token magic-beans-lp)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-minter-only (err u300))
(define-constant err-amount-zero (err u301))

(define-data-var allowed-minter principal tx-sender)

(define-data-var tokenUri (optional (string-utf8 256)) none)

(define-read-only (get-total-supply)
  (ok (ft-get-supply magic-beans-lp))
)

;; Change the minter to any other principal, can only be called the current minter
(define-public (set-minter (who principal))
  (begin
    (asserts! (is-eq tx-sender (var-get allowed-minter)) err-minter-only)
    ;; who is unchecked, we allow the minter to make whoever they like the new minter
    ;; #[allow(unchecked_data)]
    (ok (var-set allowed-minter who))
  )
)

;; Custom function to mint tokens, only available to our exchange
(define-public (mint (amount uint) (who principal))
  (begin
    (asserts! (is-eq tx-sender (var-get allowed-minter)) err-minter-only)
    (asserts! (> amount u0) err-amount-zero)
    ;; amount, who are unchecked, but we let the contract owner mint to whoever they like for convenience
    ;; #[allow(unchecked_data)]
    (ft-mint? magic-beans-lp amount who)
  )
)

(define-public (set-token-uri (uri (string-utf8 256)))
  ;; #[filter(uri)]
  (ok (var-set tokenUri (some uri)))
)

;; contracts/magic-beans-lp.clar
(define-read-only (get-decimals) 
  (ok u6)
)

(define-read-only (get-name)
  (ok "magic-beans-lp")
)

(define-read-only (get-symbol)
  (ok "MAGIC-LP")
)

(define-read-only (get-token-uri)
  (ok (var-get tokenUri))
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance magic-beans-lp who))
)

;; contracts/magic-beans-lp.clar
;; Any user can burn any amount of their own tokens
(define-public (burn (amount uint))
  (ft-burn? magic-beans-lp amount tx-sender)
)

(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-owner-only)
    (asserts! (> amount u0) err-amount-zero)
    ;; recipient is unchecked, anyone can transfer their tokens to anyone else
    ;; #[allow(unchecked_data)]
    (ft-transfer? magic-beans-lp amount sender recipient)
  )
)