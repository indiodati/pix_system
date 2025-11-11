class Payment < ApplicationRecord
  enum gateway_status: {
    pending:  "PENDING",
    paid:     "PAID",
    failed:   "FAILED",
    refunded: "REFUNDED"
  }, _prefix: :gateway
end
