require 'sinatra'
require 'killbill_client'
require 'uri'

set :kb_url, ENV['KB_URL'] || 'http://127.0.0.1:8080'
set :paypage_id, ENV['PAYPAGE_ID']
set :merchant_tx_id, ENV['MERCHANT_TX_ID']
set :order_id, ENV['ORDER_ID']
set :report_group, ENV['REPORT_GROUP']

#
# Kill Bill configuration and helpers
#

KillBillClient.url = settings.kb_url

# Multi-tenancy and RBAC credentials
options = {
    :username => 'admin',
    :password => 'password',
    :api_key => 'bob',
    :api_secret => 'lazar'
}

# Audit log data
user = 'demo'
reason = 'New subscription'
comment = 'Trigger by Sinatra'

def create_kb_account(user, reason, comment, options)
  account = KillBillClient::Model::Account.new
  account.name = "John Doe"
  account.currency = 'USD'
  account.create(user, reason, comment, options)
end

def create_kb_payment_method(account, litle_paypage_registration_id, user, reason, comment, options)
  pm = KillBillClient::Model::PaymentMethod.new
  pm.account_id = account.account_id
  pm.plugin_name = 'killbill-litle'
  pm.plugin_info = {'properties' => [{'key' => 'paypageRegistrationId', 'value' => litle_paypage_registration_id}]}
  pm.create(true, user, reason, comment, options)
end

def create_subscription(account, user, reason, comment, options)
  subscription = KillBillClient::Model::Subscription.new
  subscription.account_id = account.account_id
  subscription.product_name = 'Sports'
  subscription.product_category = 'BASE'
  subscription.billing_period = 'MONTHLY'
  subscription.price_list = 'DEFAULT'
  subscription.price_overrides = []

  # For the demo to be interesting, override the trial price to be non-zero so we trigger a charge in Litle
  override_trial = KillBillClient::Model::PhasePriceOverrideAttributes.new
  override_trial.phase_type = 'TRIAL'
  override_trial.fixed_price = 10.0
  subscription.price_overrides << override_trial
end

#
# Sinatra handlers
#

get '/' do
  @paypage_id = settings.paypage_id
  @merchant_tx_id = settings.merchant_tx_id
  @order_id = settings.order_id
  @report_group = settings.report_group

  erb :index
end

post '/charge' do
  # Create an account
  account = create_kb_account(user, reason, comment, options)

  # Add a payment method associated
  create_kb_payment_method(account, params['paypageRegistrationId'], user, reason, comment, options)

  # Add a subscription
  create_subscription(account, user, reason, comment, options)

  # Retrieve the invoice
  @invoice = account.invoices(true, options).first
  @accountId = account.account_id

  erb :charge
end

__END__

@@ layout
  <!DOCTYPE html>
  <html>
  <head>
      <meta charset="UTF-8">
      <title>Litle Demo page</title>
      <style>
          body {
              font-size:10pt;
          }
          .checkout {
              background-color:lightgrey;
              width: 50%;
          }
          #payframe {
              background-color:darkseagreen;
          }
          .testFieldTable {
              background-color:lightgrey;
          }
          #submitId {
              font-weight:bold;
              font-size:12pt;
          }
          form#fCheckout {
          }
      </style>
      <script src="https://code.jquery.com/jquery-3.1.1.min.js" type="text/javascript"></script>
      <script src="https://request-prelive.np-securepaypage-litle.com/LitlePayPage/js/payframe-client.min.js" type="text/javascript"></script>
  </head>
  <body>
    <%= yield %>
  </body>
  </html>

@@index
  <span class="image"><img src="https://drive.google.com/uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480" alt="uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480"></span>
  <article>
      <label class="amount">
        <span>Sports car, 30 days trial for only $10.00!</span>
      </label>
  </article>
  <div class="checkout">
        <h2>Checkout Form</h2>
        <form method=post id="fCheckout" name="fCheckout" action="/charge">
            <table>
                <tr><td colspan="2">
                    <div id="payframe">
                    </div>
                </td></tr>
                <tr><td>Paypage Registration ID</td><td><input type="text" id="paypageRegistrationId" name="paypageRegistrationId" readOnly="true"/> <--Hidden</td></tr>
                <tr><td>Bin</td><td><input type="text" id="bin" name="bin" readOnly="true"/> <--Hidden</td></tr>
                <tr><td></td><td align="right"><input type="submit" id="submitId">Check out</button></td></tr>
            </table>
        </form>
        <br/>
        <h3>Test Input Fields</h3>
        <table class="testFieldTable">
            <tr>
            value=<%= "'#{@customerId}'" %>
                <td>Paypage ID</td><td><input type="text" id="request$paypageId" name="request$paypageId" value=<%= "'#{@paypage_id}'" %> disabled/></td>
                <td>Merchant Txn ID</td><td><input type="text" id="request$merchantTxnId" name="request$merchantTxnId" value=<%= "'#{@merchant_tx_id}'" %> /></td>
            </tr>
            <tr>
                <td>Order ID</td><td><input type="text" id="request$orderId" name="request$orderId" value=<%= "'#{@order_id}'" %> /></td>
                <td>Report Group</td><td><input type="text" id="request$reportGroup" name="request$reportGroup" value=<%= "'#{@report_group}'" %> disabled/></td>
            </tr>
            <tr>
                <td>JS Timeout</td><td><input type="text" id="request$timeout" name="request$timeout" value="5000" disabled/></td>
            </tr>
        </table>
        <h3>Test Output Fields</h3>
        <table class="testFieldTable">
            <tr>
                <td>Response Code</td><td><input type="text" id="response$code" name="response$code" readOnly="true"/></td>
                <td>ResponseTime</td><td><input type="text" id="response$responseTime" name="response$responseTime" readOnly="true"/></td>
            </tr>
            <tr>
                <td>Response Message</td><td colspan="3"><input type="text" id="response$message" name="response$message" readOnly="true" size="100"/></td>
            </tr>
            <tr><td>&nbsp;</td><td></tr>
            <tr>
                <td>Vantiv Txn ID</td><td><input type="text" id="response$litleTxnId" name="response$litleTxnId" readOnly="true"/></td>
                <td>Merchant Txn ID</td><td><input type="text" id="response$merchantTxnId" name="response$merchantTxnId" readOnly="true"/></td>
            </tr>
            <tr>
                <td>Order ID</td><td><input type="text" id="response$orderId" name="response$orderId" readOnly="true"/></td>
                <td>Report Group</td><td><input type="text" id="response$reportGroup" name="response$reportGroup" readOnly="true"/></td>
            </tr>
            <tr><td>Type</td><td><input type="text" id="response$type" name="response$type" readOnly="true"/></td></tr>
            <tr>
                <td>Expiration Month</td><td><input type="text" id="response$expMonth" name="response$expMonth" readOnly="true"/></td>
                <td>Expiration Year</td><td><input type="text" id="response$expYear" name="response$expYear" readOnly="true"/></td>
            </tr>
            <tr><td>&nbsp;</td><td></tr>
            <tr>
                <td>First Six</td><td><input type="text" id="response$firstSix"name="response$firstSix" readOnly="true"/></td>
                <td>Last Four</td><td><input type="text" id="response$lastFour"name="response$lastFour" readOnly="true"/></td>
            </tr>
            <tr><td>Timeout Message</td><td><input type="text" id="timeoutMessage" name="timeoutMessage" readOnly="true"/></td></tr>
            <tr><td>Expected Results</td>
                <td colspan="3">
                    <textarea id="expectedResults" name="expectedResults" rows="5" cols="100" readOnly="true">
                       CC Num           - Token Generated (with simulator)
                       4100000000000001 - 1111222233330001
                       5123456789012007 - 1112333344442007
                       378310203312332  - 111344445552332
                       6011000990190005 - 1114555566660005
                     </textarea>
                </td>
            </tr>
            <tr>
                <td>Encrypted Card</td>
                <td colspan="3"><textarea id="base64enc" name="base64enc" rows="5" cols="100" readOnly="true"></textarea></td>
            </tr>
        </table>
    </div>
    <script>
        $( document ).ready(function() {
            var startTime;
            var payframeClientCallback = function(response) {
                if (response.timeout) {
                    var elapsedTime = new Date().getTime() - startTime;
                    document.getElementById('timeoutMessage').value = 'Timed out after ' +
                            elapsedTime + 'ms';// handle timeout
                }
                else {
                    document.getElementById('response$code').value = response.response;
                    document.getElementById('response$message').value = response.message;
                    document.getElementById('response$responseTime').value =
                            response.responseTime;
                    document.getElementById('response$reportGroup').value =
                            response.reportGroup;
                    document.getElementById('response$merchantTxnId').value = response.id;
                    document.getElementById('response$orderId').value = response.orderId;
                    document.getElementById('response$litleTxnId').value =
                            response.litleTxnId;
                    document.getElementById('response$type').value = response.type; document.getElementById('response$lastFour').value = response.lastFour; document.getElementById('response$firstSix').value = response.firstSix; document.getElementById('paypageRegistrationId').value =
                            response.paypageRegistrationId;
                    document.getElementById('bin').value = response.bin;
                    document.getElementById('response$expMonth').value = response.expMonth;
                    document.getElementById('response$expYear').value = response.expYear;
                    document.getElementById('fCheckout').submit();
                }
            };

            var configure = {
                "paypageId":document.getElementById("request$paypageId").value,
                "style":"test",
                "height":"200px",
                "reportGroup":document.getElementById("request$reportGroup").value,
                "timeout":document.getElementById("request$timeout").value,
                "div": "payframe",
                "callback": payframeClientCallback,
                "showCvv": true,
                "months": {
                    "1":"January",
                    "2":"February",
                    "3":"March",
                    "4":"April",
                    "5":"May",
                    "6":"June",
                    "7":"July",
                    "8":"August",
                    "9":"September",
                    "10":"October",
                    "11":"November",
                    "12":"December"
                },
                "numYears": 8,
                "tooltipText": "A CVV is the 3 digit code on the back of your Visa, MasterCard and Discover or a 4 digit code on the front of your American Express",
                "tabIndex": {
                    "cvv":1,
                    "accountNumber":2,
                    "expMonth":3,
                    "expYear":4
                },
                "placeholderText": {
                    "cvv":"CVV",
                    "accountNumber":"Account Number"
                }
            };
            if(typeof LitlePayframeClient === 'undefined') {
                //This means we couldn't download the payframe-client javascript library
                alert("Couldn't download payframe-client javascript");
            }
            var payframeClient = new LitlePayframeClient(configure);
            payframeClient.autoAdjustHeight();
            document.getElementById("fCheckout").onsubmit = function(){
                var message = {
                    "id":document.getElementById("request$merchantTxnId").value,
                    "orderId":document.getElementById("request$orderId").value
                };
                startTime = new Date().getTime();
                payframeClient.getPaypageRegistrationId(message);
                return false;
            };
        });
    </script>

@@charge
  <h2>Thanks! Here is your invoice:</h2>
  <ul>
    <% @invoice.items.each do |item| %>
      <li><%= "subscription_id=#{item.subscription_id}" %></li>
      <li><%= "amount=#{item.amount}" %></li>
      <li><%= "phase=sports-monthly-trial" %></li>
      <li><%= "start_date=#{item.start_date}" %></li>
    <% end %>
  </ul>
  You can verify the Kill Bill Invoice at <a href="<%= "http://localhost:8081/kaui/accounts/#{@accountId}/invoices/#{@invoice.invoice_id}" %>"><%= "Invoice #{@invoice.invoice_id}" %></a>.
