(impl-trait .traits.ft-trait)
(define-fungible-token magic-beans)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-amount-zero (err u101))

(define-data-var tokenUri (optional (string-utf8 256)) none)

(define-read-only (get-symbol)
  (ok "MAGIC")
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance magic-beans who))
)

(define-public (set-token-uri (uri (string-utf8 256)))
  ;; #[filter(uri)]
  (ok (var-set tokenUri (some uri)))
)

(define-read-only (get-name)
  (ok "magic-beans")
)

(define-read-only (get-decimals)
  (ok u0)
)

(define-read-only (get-token-uri)
  (ok (var-get tokenUri))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply magic-beans))
)

;; Custom function to mint tokens, only available to the contract owner
(define-public (mint (amount uint) (who principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-amount-zero)
    ;; amount, who are unchecked, but we let the contract owner mint to whoever they like for convenience
    ;; #[allow(unchecked_data)]
    (ft-mint? magic-beans amount who)
  )
)

(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-owner-only)
    (asserts! (> amount u0) err-amount-zero)
    ;; recipient is unchecked, anyone can transfer their tokens to anyone else
    ;; #[allow(unchecked_data)]
    (ft-transfer? magic-beans amount sender recipient)
  )
)