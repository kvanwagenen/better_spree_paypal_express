FactoryGirl.define do
  factory :paypal_express_checkout, class: Spree::PaypalExpressCheckout do
    transaction_id "AB1234567"
  end
end