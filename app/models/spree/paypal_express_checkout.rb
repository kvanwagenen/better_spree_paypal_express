module Spree
  class PaypalExpressCheckout < ActiveRecord::Base
    def imported
    end
    
    def actions
      %w{credit}
    end
  end
end