class PagseguroConfiguration < Configuration

  # the url parameters should not need to be changed (unless pagseguro changes the api or something other major change)
  preference :pagseguro_sandbox_url, :string, :default => "https://localhost/security/webpagamentos/webpagto.aspx"
  preference :pagseguro_billing_url, :string, :default => "https://pagseguro.uol.com.br/security/webpagamentos/webpagto.aspx"
  preference :pagseguro_shipping_url, :string, :default => "https://pagseguro.uol.com.br/CalculaFrete.aspx"
  
  # these are just default preferences of course, you'll need to change them to something meaningful
  preference :account, :string, :default => "your_account@example.com"
#  preference :ipn_notify_host, :string, :default => "http://localhost:3000"
  preference :success_url, :string, :default => "http://localhost:3000/checkout/success"
  
  validates_presence_of :name
  validates_uniqueness_of :name
end