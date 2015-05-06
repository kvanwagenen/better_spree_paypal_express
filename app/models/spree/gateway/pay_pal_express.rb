require 'paypal-sdk-merchant'
module Spree
  class Gateway::PayPalExpress < Gateway
    preference :login, :string
    preference :password, :string
    preference :signature, :string
    preference :server, :string, default: 'sandbox'
    preference :solution, :string, default: 'Mark'
    preference :landing_page, :string, default: 'Billing'
    preference :logourl, :string, default: ''

    def supports?(source)
      true
    end

    def provider_class
      ::PayPal::SDK::Merchant::API
    end

    def provider
      ::PayPal::SDK.configure(
        :mode      => preferred_server.present? ? preferred_server : "sandbox",
        :username  => preferred_login,
        :password  => preferred_password,
        :signature => preferred_signature)
      provider_class.new
    end

    def auto_capture?
      true
    end

    def method_type
      'paypal'
    end

    def purchase(amount, express_checkout, gateway_options={})
      pp_details_request = provider.build_get_express_checkout_details({
        :Token => express_checkout.token
      })
      pp_details_response = provider.get_express_checkout_details(pp_details_request)

      pp_request = provider.build_do_express_checkout_payment({
        :DoExpressCheckoutPaymentRequestDetails => {
          :PaymentAction => "Sale",
          :Token => express_checkout.token,
          :PayerID => express_checkout.payer_id,
          :PaymentDetails => pp_details_response.get_express_checkout_details_response_details.PaymentDetails
        }
      })

      pp_response = provider.do_express_checkout_payment(pp_request)
      if pp_response.success?
        # We need to store the transaction id for the future.
        # This is mainly so we can use it later on to refund the payment if the user wishes.
        transaction_id = pp_response.do_express_checkout_payment_response_details.payment_info.first.transaction_id
        express_checkout.update_column(:transaction_id, transaction_id)
        # This is rather hackish, required for payment/processing handle_response code.
        Class.new do
          def success?; true; end
          def authorization; nil; end
        end.new
      else
        class << pp_response
          def to_s
            errors.map(&:long_message).join(" ")
          end
        end
        pp_response
      end
    end

    def refund(payment, amount)
      refund_type = payment.amount == amount.to_f ? "Full" : "Partial"
      refund_transaction = provider.build_refund_transaction({
        :TransactionID => payment.source.transaction_id,
        :RefundType => refund_type,
        :Amount => {
          :currencyID => payment.currency,
          :value => amount },
        :RefundSource => "any" })
      refund_transaction_response = provider.refund_transaction(refund_transaction)
      if refund_transaction_response.success?
        payment.source.update_attributes({
          :refunded_at => Time.now,
          :refund_transaction_id => refund_transaction_response.RefundTransactionID,
          :state => "refunded",
          :refund_type => refund_type
        })

        payment.class.create!(
          :order => payment.order,
          :source => payment,
          :payment_method => payment.payment_method,
          :amount => amount.to_f.abs * -1,
          :response_code => refund_transaction_response.RefundTransactionID,
          :state => 'completed'
        )
      end
      refund_transaction_response
    end

    # Called when order is canceled or credited through the admin interface
    def credit(credit_cents, response_code, gateway_options)

      # Get payment by grabbing identifier from order id
      payment = Spree::Payment.find_by_identifier(gateway_options[:order_id].split('-').last)
      
      # Convert credit amount to float
      amount = (credit_cents * 0.01).round(2)

      # If told to credit 0, credit the full amount instead
      if amount == 0
        amount = payment.amount.to_f
      end

      # Process the refund
      refund_response = refund(payment, amount)
      response = OpenStruct.new({:success? => refund_response.success?})
      response.instance_eval do
        def set_message(message)
          @message = message
        end
        def to_s
          @message.nil? ? "Error refunding paypal transaction" : @message 
        end
      end
      unless refund_response.success?
        response.set_message(refund_response.errors.first.long_message)
      end
      response
    end
  end
end

#   payment.state = 'completed'
#   current_order.state = 'complete'
