class CashOut < ApplicationRecord
  enum gateway_status: {
    pending:  "PENDING",
    paid:     "PAID",
    failed:   "FAILED"
  }, _prefix: :gateway
end
