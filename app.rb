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
  subscription.create(user, reason, comment, nil, true, options)
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
  create_kb_payment_method(account, params['response$paypageRegistrationId'], user, reason, comment, options)

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
    <script src="https://code.jquery.com/jquery-3.1.1.min.js" type="text/javascript"></script>
    <script src="https://request-prelive.np-securepaypage-litle.com/LitlePayPage/litle-api2.js" type="text/javascript"></script>
    <script>
      $(document).ready(function() {
        function setLitleResponseFields(response) {
            document.getElementById('response$code').value = response.response;
            document.getElementById('response$message').value = response.message;
            document.getElementById('response$responseTime').value = response.responseTime;
            document.getElementById('response$litleTxnId').value = response.litleTxnId;
            document.getElementById('response$type').value = response.type;
            document.getElementById('response$firstSix').value = response.firstSix;
            document.getElementById('response$lastFour').value = response.lastFour;
        }
        function submitAfterLitle (response) {
          setLitleResponseFields(response);
          document.getElementById('fCheckout').submit();
        }
        function timeoutOnLitle () {
          alert("We are experiencing technical difficulties.  Please try again later or call 555-555-1212 (timeout)");
        }
        function onErrorAfterLitle (response) {
          setLitleResponseFields(response);
          if(response.response == '871') {
            alert("Invalid card number.  Check and retry. (Not Mod10)");
          }
          else if(response.response == '872') {
            alert("Invalid card number.  Check and retry. (Too short)");
          }
          else if(response.response == '873') {
            alert("Invalid card number.  Check and retry. (Too long)");
          }
          else if(response.response == '874') {
            alert("Invalid card number.  Check and retry. (Not a number)");
          }
          else if(response.response == '875') {
            alert("We are experiencing technical difficulties. Please try again later or call 555-555-1212");
          }
          else if(response.response == '876') {
            alert("Invalid card number.  Check and retry. (Failure from Server)");
          }
          else if(response.response == '881') {
            alert("Invalid card validation code. Check and retry. (Not a number)");
          }
          else if(response.response == '882') {
            alert("Invalid card validation code. Check and retry. (Too short)");
          }
          else if(response.response == '883') {
            alert("Invalid card validation code. Check and retry. (Too long)");
          }
          else if(response.response == '889') {
            alert("889 - We are experiencing technical difficulties. Please try again later or call 555-555-1212");
          }
          return false;
        }
        var formFields = {
          "accountNum" : document.getElementById('ccNum'),
          "cvv2" : document.getElementById('cvv2Num'),
          "paypageRegistrationId" : document.getElementById('response$paypageRegistrationId'),
          "bin" : document.getElementById('response$bin')
        };
        $("#submitId").click(function() {
          // clear test fields
          setLitleResponseFields({"response":"", "message":""});
          var litleRequest = {
            "paypageId" : document.getElementById("request$paypageId").value,
            "reportGroup" : document.getElementById("request$reportGroup").value,
            "orderId" : document.getElementById("request$orderId").value,
            "id" : document.getElementById("request$merchantTxnId").value,
            "url" : "https://request-prelive.np-securepaypage-litle.com"
          };
          new LitlePayPage().sendToLitle(litleRequest, formFields, submitAfterLitle, onErrorAfterLitle, timeoutOnLitle, 15000);
          return false;
        });
      });
    </script>
  </head>
  <body>
    <%= yield %>
  </body>
  <script>
    /* This is an example of how to handle being unable to download the litle-api2 */
    function callLitle() {
      if(typeof new LitlePayPage() != 'object') {
        alert("We are experiencing technical difficulties. Please try again later or call 555-555-1212 (API unavailable)" );
      }
    }
  </script>
  </html>

@@index
  <span class="image"><img src="https://drive.google.com/uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480" alt="uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480"></span>
  <article>
      <label class="amount">
        <span>Sports car, 30 days trial for only $10.00!</span>
      </label>
  </article>
  <h2>Checkout Form</h2>
  <form method=post id="fCheckout" name="fCheckout" action="/charge">
    <input type="hidden" id="request$paypageId" name="request$paypageId" value=<%= "'#{@paypage_id}'" %> />
    <input type="hidden" id="request$merchantTxnId" name="request$merchantTxnId" value=<%= "'#{@merchant_tx_id}'" %> />
    <input type="hidden" id="request$orderId" name="request$orderId" value=<%= "'#{@order_id}'" %> />
    <input type="hidden" id="request$reportGroup" name="request$reportGroup" value=<%= "'#{@report_group}'" %> />
    <table>
      <tr>
        <td>First Name</td>
        <td>
          <input type="text" id="fName" name="fName" size="20">
        </td>
      </tr>
      <tr>
        <td>Last Name</td>
        <td>
          <input type="text" id="lName" name="lName" size="20">
        </td>
      </tr>
      <tr>
        <td>Credit Card</td>
        <td>
          <input type="text" id="ccNum" name="ccNum" size="20">
        </td>
      </tr>
      <tr>
        <td>CVV</td>
        <td>
          <input type="text" id="cvv2num" name="cvv2num" size="5">
        </td>
      </tr>
      <tr>
        <td>Exp Date</td>
        <td>
          <input type="text" id="expDate" name="expDate" size="5">
        </td>
      </tr>
      <tr>
        <td>&nbsp;</td>
        <td></td>
      </tr>
      <tr>
        <td></td>
        <td align="right">
          <script>
            document.write('<button type="button" id="submitId" onclick="callLitle()">Check out with PayPage</button>');
          </script>
          <noscript>
            <button type="button" id="submitId">Enable JavaScript or call us at 555-555-1212</button>
          </noscript>
        </td>
      </tr>
    </table>
    <input type="hidden" id="response$paypageRegistrationId" name="response$paypageRegistrationId" readOnly="true" value=""/>
    <input type="hidden" id="response$bin" name="response$bin" readOnly="true"/>
    <input type="hidden" id="response$code" name="response$code" readOnly="true"/>
    <input type="hidden" id="response$message" name="response$message" readOnly="true"/>
    <input type="hidden" id="response$responseTime" name="response$responseTime" readOnly="true"/>
    <input type="hidden" id="response$type" name="response$type" readOnly="true"/>
    <input type="hidden" id="response$litleTxnId" name="response$litleTxnId" readOnly="true"/>
    <input type="hidden" id="response$firstSix" name="response$firstSix" readOnly="true"/>
    <input type="hidden" id="response$lastFour" name="response$lastFour" readOnly="true"/>
  </form>

@@charge
  <h2>Thanks! Here is your invoice:</h2>
  <ul>
    <% @invoice.items.each do |item| %>
      <li><%= "subscription_id = #{item.subscription_id}" %></li>
      <li><%= "amount = #{item.amount}" %></li>
      <li><%= "phase = sports-monthly-trial" %></li>
      <li><%= "start_date = #{item.start_date}" %></li>
    <% end %>
  </ul>
  <h3>You can verify the Kill Bill Invoice at <a href="<%= "http://localhost:8081/kaui/accounts/#{@accountId}/invoices/#{@invoice.invoice_id}" %>"><%= "Invoice #{@invoice.invoice_id}" %></a>.</h3>
