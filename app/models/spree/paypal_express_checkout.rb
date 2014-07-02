module Spree
  class PaypalExpressCheckout < ActiveRecord::Base
    attr_accessible :refunded_at, :refund_transaction_id, :state, :refund_type
  end
end