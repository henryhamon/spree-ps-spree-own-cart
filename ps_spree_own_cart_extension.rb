# Uncomment this if you reference any of your controllers in activate
require_dependency 'application'

class PsSpreeOwnCartExtension < Spree::Extension
  version "0.99"
  description "Support for brazilian online payment service PagSeguro using Spree's own cart."
  url "http://github.com/edmundo/spree-ps-spree-own-cart/tree/master"

  def activate
    Address.class_eval do
      validates_presence_of :number
      validates_presence_of :borough
      validates_presence_of :area_code
      validates_numericality_of :area_code, :integer_only => true
    end

    # Add a partial for PagSeguro Payment txns
    Admin::OrdersController.class_eval do
      before_filter :add_ps_own_cart_txns, :only => :show
      
      def add_ps_own_cart_txns
        @txn_partials << 'ps_own_cart_txns'
      end
    end
    
#    # Add a filter to the OrdersController so that if user is reaching us from an email link we can 
#    # associate the order with the user (once they log in)
#    OrdersController.class_eval do
#      before_filter :associate_order, :only => :show
#      private
#      def associate_order  
#        return unless payer_id = params[:payer_id]
#        orders = Order.find(:all, :include => :pagseguro_payment, :conditions => ['pagseguro_payments.payer_id = ? AND orders.user_id is null', payer_id])
#        orders.each do |order|
#          order.update_attribute("user", current_user)
#        end
#      end
#    end

    OrdersHelper.class_eval do
      def to_iso(text)
        Iconv.iconv('iso-8859-1', 'utf-8', text).to_s
      end

      def to_utf(text)
        Iconv.iconv('utf-8', 'iso-8859-1', text).to_s
      end
    end

    OrdersController.class_eval do
      before_filter :set_charset, :only => :transmit
      def set_charset
        headers["Content-Type"] = "text/html; charset=ISO-8859-1"
      end
      
      include Spree::Pagseguro::PostsData

      before_filter :load_object, :only => [:checkout, :confirmation, :transmit, :finished]
      skip_before_filter :verify_authenticity_token, :only => [:transmit]

#      skip_before_filter :verify_authenticity_token, :only => [:confirmation]

      def confirmation
        # Mark the order as "ready to transmit"
        if @order.state == "shipment"
          @order.next!
        end

      end

      def transmit
        require 'iconv'

        if Spree::Pagseguro::Config[:always_use_sandbox] || RAILS_ENV == 'development'
          pagseguro_url = Spree::Pagseguro::Config[:sandbox_billing_url]
        else
          pagseguro_url = Spree::Pagseguro::Config[:billing_url]
        end

        # Mark the order as waiting for payment response if it was ready to transmit and clean the session.
        if @order.state == "ready_to_transmit"
          @order.wait_for_payment_response!

          @order.update_attribute("ip_address", request.env['REMOTE_ADDR'] || "unknown")
          @order.update_attribute("checkout_complete", true) 
          
          # Get rid of the order in the session quick and put it in another place just for the
          # final message.
          session[:transmited_order_id] = session[:order_id]
          session[:order_id] = nil
        end

#        payload = Spree::Pagseguro::CheckoutData.data_to_send(@order)

#        # If we are waiting for payment response the checkout is complete
#        if object.checkout_complete
#          # Transmit the form to PagSeguro
#          if Spree::Pagseguro::Config[:always_use_sandbox] || RAILS_ENV == 'development'
#            response = post(pagseguro_url, payload, 'Content-Length' => "#{payload.size}")
#          else
#            response = ssl_post(pagseguro_url, payload, 'Content-Length' => "#{payload.size}")
#          end

#          render :inline => response
#        end
         render :layout => false
      end

      def finished
        # Here is just rendered the finish message.
      end

    end


    # Modify the transitions in core.
    fsm = Order.state_machines['state']

    # Delete transitions that should not be used.
    fsm.events['next'].transitions.delete_if { |t| t.options[:to] == "creditcard_payment" && t.options[:from] == "shipment" }
    fsm.events['previous'].transitions.delete_if { |t| t.options[:to] == "shipment" && t.options[:from] == "creditcard_payment" }
    fsm.events['next'].transitions.delete_if { |t| t.options[:to] == "authorized" && t.options[:from] == "creditcard_payment" }
    fsm.events['edit'].transitions.delete_if { |t| t.options[:to] == "in_progress" && t.options[:from] == "creditcard_payment" }
    fsm.events['capture'].transitions.delete_if { |t| t.options[:to] == "captured" && t.options[:from] == "authorized" }
    fsm.events['ship'].transitions.delete_if { |t| t.options[:to] == "shipped" && t.options[:from] == "captured" }

    # Delete states that should not be used.
    fsm.states.delete('creditcard_payment')
    fsm.states.delete('authorized')
    fsm.states.delete('captured')

    # add a PagSeguroPayment association to the Order model
    Order.class_eval do
      has_one :pagseguro_payment

      fsm.event :next do
        transition :to => 'ready_to_transmit', :from => 'shipment'
      end
  
      fsm.event :previous do
        transition :to => 'shipment', :from => 'ready_to_transmit'
      end
  
      fsm.event :edit do
        transition :to => 'in_progress', :from => 'ready_to_transmit'
      end
  
      fsm.event :wait_for_payment_response do
        transition :to => 'waiting_for_payment_response', :from => 'ready_to_transmit'
      end
      fsm.after_transition :to => 'waiting_for_payment_response', :do => lambda {|order| order.update_attribute(:checkout_complete, true)}  
  
      fsm.event :approve do
        transition :to => 'ready_to_ship', :from => 'waiting_for_payment_response'
      end
      fsm.after_transition :to => 'ready_to_ship', :do => :complete_order  
  
      fsm.event :cancel do
        transition :to => 'canceled', :from => 'waiting_for_payment_response'
      end

      fsm.event :ship do
        transition :to => 'shipped', :from => 'ready_to_ship'
      end
    end

  
    # Add support for internationalization to this extension.
    Globalite.add_localization_source(File.join(RAILS_ROOT, 'vendor/extensions/ps_spree_own_cart/lang/ui'))

    # Add the administration link. (Only as a placeholder)
    Admin::ConfigurationsController.class_eval do
      before_filter :add_ps_spree_own_cart_link, :only => :index
      def add_ps_spree_own_cart_link
        @extension_links << {:link => admin_pagseguro_settings_path , :link_text => Globalite.localize(:ext_ps_spree_own_cart), :description => Globalite.localize(:ext_ps_spree_own_cart_description)}
      end
    end
  end

  def self.require_gems(config)
    config.gem 'activerecord-tableless', :lib => 'tableless'
  end
end