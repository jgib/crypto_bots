#!/usr/bin/env ruby

require 'pp'
require 'json'
require 'date'
require 'io/console'
require 'binance-ruby'

# Modify the Float class so we can round down.
class Float
  def floor2(exp = 0)
    multiplier = 10 ** exp
    ((self * multiplier).floor).to_f / multiplier.to_f
  end
end

# Get decryption password
system("clear")
print "Decryption Passphrase: "
pass = STDIN.noecho(&:gets).chomp
puts ""

##########
# CONFIG #
##########

ROUND         = 2                                                 # Ammount to round currency decimals.
DEBUG         = true                                              # Toggle debug output.
ERROR         = "2> /dev/null"                                    # Blackhole error output.
HOME          = "/home/admin/ruby/"                               # Home directory of keys file.
GPG           = "/usr/bin/gpg"                                    # Path to gpg.
KEYS          = "#{HOME}keys.gpg"                                 # Path and filename of encrypted keys file.
DECRYPT       = "#{GPG} --passphrase #{pass} -d #{KEYS} #{ERROR}" # Decryption command.
PAIR1         = "BNB"                                             # First half of currency pair.
PAIR2         = "USDT"                                            # Second half of currency pair.
SYMBOL        = "#{PAIR1}#{PAIR2}"                                # Currency pair.
INTERVAL      = "5m"                                              # Candlestick intervals.  Options are: 1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 8h, 12h, 1d, 3d, 1w, 1M
BUY_PERCENT   = 1                                                 # Percent of price to buy at.  (1 - 0.02) = 2% under.  (1 + 0.02) = 2% over.
SELL_PERCENT  = 1                                                 # Percent of price to sell at. (1 - 0.02) = 2% under.  (1 + 0.02) = 2% over.
TRADE_PERCENT = 1                                                 # Percent of total capital to trade.
PERIOD        = 20                                                # Number of candles used to calculate SMA and BBANDS.
STOP_PERCENT  = 1 - 0.02                                          # Percent past the buy price to exit the trade.  1 - 0.01 = 1% past buy price.
STOP_WAIT     = 60 * 60 * 1.5                                     # Time to wait in seconds after stop condition reached.
FEE           = 0.0005                                            # Trade fee for buy and sell.
REQUEST_TIME  = 0.3                                               # Time in seconds to wait before sending request. (0.15 Isn't always long enough for API data to update on server).

##########
# CONFIG #
##########

#########
# NOTES #
#########

# SMA = Sum of closing prices over n periods / by n
# Middle Band = 20-day simple moving average (SMA)
# Upper  Band = 20-day SMA + (20-day standard deviation of price * 2)
# Lower  Band = 20-day SMA - (20-day standard deviation of price * 2)

# Documentation: https://github.com/binance-exchange/binance-official-api-docs/blob/master/rest-api.md

# Rate Limits:
#   REQUESTS: 1200 / MIN
#     +->       20 / SEC
#   ORDERS:     10 / SEC
#   ORDERS: 100000 / DAY

#   A 429 will be returned by webserver when rate limit is exceeded.
#   Repeated rate limit violations will result in 418 return code and result in IP ban.
#   Other Response Codes:
#    4XX malformed request, client side error.
#    5XX internal errors, server side error.
#    504 API successfully sent message but did not get response within timeout.
#      Request may succeed or fail, status is unknown.

#   API Keys are passed to REST via 'X-MBX-APIKEY' header
#   All timestamps for API are in milliseconds, the default is 5000.
#     This should probably be set to something less.

#   Reference for binance API: https://github.com/jakenberg/binance-ruby

# IDEA: Add function that scans all currency pairs on exchange, looking for the most volitle (and takes into consideration volume) and selects that pair for trading (would also need to
#       issue a market order if the base currency isn't currently in our balance).

#########
# NOTES #
#########

#########
# TO DO #
#########

# Add email functionality
# Re-write algo logic, Ruby has limited recursion capability and this will eventually be a problem for exceptionally long trade swings (I'm guessing it will be good for at least 3 - 6
# hours.

#########
# TO DO #
#########

def get_timestamp()
  # INPUT:  NONE
  # OUTPUT: Timestamp in format TIME ::: EPOCH
  time  = Time.now.to_s
  epoch = Time.now.to_f.round(4)
  return("#{time} ::: #{epoch}")
end

def debug(text)
  # INPUT:  STRING
  # OUTPUT: Displays string input prepended with timestamp if DEBUG is set to true in config.
  if DEBUG == true
    time = get_timestamp
    STDERR.puts("#{time} ::: #{text}")
  end
end

def wait(seconds)
  # INPUT:  INTEGER or FLOAT
  # OUTPUT: NONE
  debug("Waiting #{seconds} seconds...")
  sleep(seconds)
end

def decrypt()
  # INPUT:  NONE
  # OUTPUT: ARRAY, In order of: [API Key, Secret Key, Email Address, Email Password, Destination Email(s)]
  output   = Array.new
  debug("Starting decryption of #{KEYS}")
  raw_data = JSON.parse(`#{DECRYPT}`)
  raw_data.each do |array|
    if(array[0] == "API Key")
      debug("Captured API Key")
      output[0] = array[1]
    elsif(array[0] == "Secret Key")
      debug("Captured Secret Key")
      output[1] = array[1]
    elsif(array[0] == "Email")
      debug("Captured senders email address")
      output[2] = array[1]
    elsif(array[0] == "Password")
      debug("Captured senders email password")
      output[3] = array[1]
    elsif(array[0] == "Dest")
      debug("Captured destination email addresses")
      output[4] = array[1]
    end
  end
  debug("Decryption of #{KEYS} finished")
  return(output)
end

def get_candles()
  # INPUT:  NONE
  # OUTPUT: ARRAY of ARRAYS, In the form: [[Open Time, Open, High, Low, Close, Volume, Close Time, Quote Asset Volume, Number of Trades, Take Buy Base Asset Volume, 
  #                                         Taker Buy Quote Asset Volume, Ignore], ..... ]
  wait(REQUEST_TIME)
  debug("Getting candlestick data")
  begin
    output = Binance::Api.candlesticks!(interval: "#{INTERVAL}", symbol: "#{SYMBOL}", limit: "#{PERIOD}")
  rescue Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(get_candles())
  else
    return(output)
  end
end

def sma(prices)
  # INPUT:  ARRAY of prices.
  # OUTPUT: FLOAT, SMA.
  debug("Calculating SMA")
  total = 0
  prices.each do |price|
    total = total + price
  end
  output = total / PERIOD
  debug("SMA is #{output}")
  return(output)
end

def std_dev(prices,sma)
  # INPUT:  ARRAY and FLOAT
  # OUTPUT: FLOAT, Standard Deviation.
  debug("Calculating Standard Deviation")
  distance_to_mean = Array.new
  debug("Calculating distance to mean")
  prices.each do |price|
    distance_to_mean.push((price.to_f - sma) ** 2)
  end
  means_sum = 0
  debug("Summing distances to mean")
  distance_to_mean.each do |dst|
    means_sum = means_sum + dst
  end
  debug("Square root of sum over period")
  output    = Math.sqrt(means_sum / PERIOD)
  debug("Standard Deviation is #{output}")
  return(output)
end

def calc_bbands(candles)
  # INPUT:  ARRAY of ARRAYS, Candle Data from function above.
  # OUTPUT: ARRAY, [middle band, upper band, lower band]
  i = 1
  closing_prices = Array.new
  candles.each do |candle|
    debug("Getting candle #{i}")
    open_time  = candle[0].to_i
    open       = candle[1].to_f
    high       = candle[2].to_f
    low        = candle[3].to_f
    close      = candle[4].to_f
    volume     = candle[5].to_f
    close_time = candle[6].to_i
    num_trades = candle[8].to_i
    closing_prices.push(close)
    i = i + 1
  end
  sma         = sma(closing_prices)
  std_dev     = std_dev(closing_prices,sma)
  output      = Array.new
  middle_band = sma
  output.push(middle_band)
  debug("Middle Band is #{middle_band}")
  upper_band  = sma + (std_dev * 2)
  output.push(upper_band)
  debug("Upper Band is #{upper_band}")
  lower_band  = sma - (std_dev * 2)
  output.push(lower_band)
  debug("Lower Band is #{lower_band}")
  return(output)
end

def limit_order(side,qty,price)
  # INPUT:  STRING, FLOAT, FLOAT.
  # OUTPUT: INTEGER, Order ID.
  wait(REQUEST_TIME)
  debug("Initiating limit order: side=#{side}, qty=#{qty}, price=#{price}")
  begin
    order_id = Binance::Api::Order.create!(side: "#{side}", quantity: "#{qty}", price: "#{price}", symbol: "#{SYMBOL}", timeInForce: "GTC", type: "LIMIT")[:orderId].to_s
    debug("Order ID: #{order_id}")
  rescue Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(limit_order(side,qty,price))
  else
    return(order_id)
  end
end

def market_order(side,qty)
  # INPUT:  STRING, FLOAT.
  # OUTPUT: INTEGER, Order ID.
  wait(REQUEST_TIME)
  debug("Initiating market order: side=#{side}, qty=#{qty}")
  begin
    order_id = Binance::Api::Order.create!(side: "#{side}", quantity: "#{qty}", symbol: "#{SYMBOL}", type: "MARKET")[:orderId].to_s
    debug("Order ID: #{order_id}")
  resuce Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(market_order(side,qty))
  else
    return(order_id)
  end
end

def cancel_order(order_id)
  # INPUT:  INTEGER, Order ID
  # OUTPUT: NONE
  wait(REQUEST_TIME)
  debug("Preparing to cancel order: #{order_id}")
  begin
    Binance::Api::Order.cancel!(orderId: "#{order_id}", symbol: "#{SYMBOL}")
    debug("Order: #{order_id} canceled")
  rescue Binance::Api::Error => error
    debug("ERROR"))
    pp error
    return(cancel_order(order_id))
  end
end

def check_order_status(order_id)
  # INPUT:  INTEGER, Order ID
  # OUTPUT: STRING, Order Status.
  wait(REQUEST_TIME)
  debug("Checking order status of: #{order_id}")
  begin
    data    = Binance::Api::Order.all!(orderId: "#{order_id}", symbol: "#{SYMBOL}")
  rescue Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(check_order_status(order_id))
  else
    if(data.is_a?(Array))
      if(data[0].is_a?(Hash))
        if(data[0].key?(:status))
          status = data[0][:status].to_s
          debug("Status is: #{status}")
          return(status)
        else
          return(check_order_status(order_id))
        end
      else
        return(check_order_status(order_id))
      end
    else
      return(check_order_status(order_id))
    end
  end
end

def get_order_price(order_id)
  # INPUT:  INTEGER, Order ID
  # OUTPUT: FLOAT, Price of Order.
  wait(REQUEST_TIME)
  debug("Checking order price of: #{order_id}")
  begin
    price = Binance::Api::Order.all!(orderId: "#{order_id}", symbol: "#{SYMBOL}")[0][:price].to_f
    debug("Price is: #{price}")
  resuce Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(get_order_price(order_id)
  else
    return(price)
  end
end

def get_ticker()
  # INPUT:  NONE
  # OUTPUT: FLOAT, Ticker Price.
  wait(REQUEST_TIME)
  debug("Getting ticker price")
  begin
    ticker_price = Binance::Api.ticker!(symbol: "#{SYMBOL}", type: "price")[:price].to_s
    debug("Ticker price is: #{ticker_price}")
  rescue Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(get_ticker())
  else
    return(ticker_price)
  end
end

def get_balance()
  # INPUT:  NONE
  # OUTPUT: ARRAY, [1st Trading Pair, 2nd Trading Pair]
  wait(REQUEST_TIME)
  debug("Getting account balances")
  output   = Array.new
  begin
    balances = Binance::Api::Account.info!
  resuce Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(get_balance())
  else
    balances[:balances].each do |index|
      if(index[:asset] == PAIR1)
        balance1 = index[:free]
        debug("Balance for #{PAIR1} is: #{balance1}")
        output.push(balance1)
      elsif(index[:asset] == PAIR2)
        balance2 = index[:free]
        debug("Balance for #{PAIR2} is: #{balance2}")
        output.push(balance2)
      end
    end
    return(output)
  end
end

def price_filter()
  # INPUT:  NONE
  # OUTPUT: NONE
  wait(REQUEST_TIME)
  debug("Getting price filter")
  begin
    currencies = Binance::Api.exchange_info![:symbols]
  resuce Binance::Api::Error => error
    debug("ERROR")
    pp error
    return(price_filter())
  else
    currencies.each do |currency|
      if(currency[:symbol] == "#{SYMBOL}")
        filters = currency[:filters]
        filters.each do |filter|
          if(filter[:filterType] == "PRICE_FILTER")
            debug("Min price is: #{filter[:minPrice]}")
            debug("Max price is: #{filter[:maxPrice]}")
            debug("Tick size is: #{filter[:tickSize]}")
          end
        end
      end
    end
  end
end

def trade(side)
  # INPUT:  STRING, buy or sell
  # OUTPUT: NONE
  debug("Checking if we are buying or selling")
  bbands   = calc_bbands(get_candles())
  mband    = bbands[0].to_f.floor2(ROUND)
  uband    = bbands[1].to_f.floor2(ROUND)
  lband    = bbands[2].to_f.floor2(ROUND)
  ticker   = get_ticker().to_f.floor2(ROUND)
  balances = get_balance()
  balance1 = balances[0].to_f.floor2(ROUND)
  balance2 = balances[1].to_f.floor2(ROUND)
  debug("bbands   = #{bbands}")
  debug("mband    = #{mband}")
  debug("uband    = #{uband}")
  debug("lband    = #{lband}")
  debug("ticker   = #{ticker}")
  debug("balances = #{balances}")
  debug("balance1 = #{balance1}")
  debug("balance2 = #{balance2}")
  if(side == "buy")
    debug("We are buying")
    debug("Is ticker price: #{ticker} >= lband: #{lband}")
    if(ticker >= lband)
      debug("True")
      debug("Calculating price: #{lband} * #{BUY_PERCENT}")
      price    = (lband * BUY_PERCENT).floor2(ROUND)
      debug("Price is: #{price}")
      debug("Calculating quantity: #{balance2} / #{price}")
      qty      = (balance2 / price).floor2(ROUND)
      debug("Quantity is: #{qty}")
      order_id = limit_order("BUY",qty,price)
      return(order_id)
    else
      debug("False")
      debug("Calculating price: #{ticker} * #{BUY_PERCENT}")
      price    = (ticker * BUY_PERCENT).floor2(ROUND)
      debug("Price is: #{price}")
      debug("Calculating quantity: #{balance2} / #{price}")
      qty      = (balance2 / price).floor2(ROUND)
      debug("Quantity is: #{qty}")
      order_id = limit_order("BUY",qty,price)
      return(order_id)
    end
  end
  if(side == "sell")
    debug("We are selling")
    debug("Is ticker price: #{ticker} <= mband: #{mband}")
    if(ticker <= mband)
      debug("True")
      debug("Calculating price: #{mband} * #{SELL_PERCENT}")
      price    = (mband * SELL_PERCENT).floor2(ROUND)
      debug("Price is: #{price}")
      debug("Calculating quantity: #{balance1}")
      qty      = balance1.floor2(ROUND)
      debug("Quantity is: #{qty}")
      order_id = limit_order("SELL",qty,price)
      return(order_id)
    else
      debug("False")
      debug("Calculating price: #{ticker} * #{SELL_PERCENT}")
      price    = (ticker * SELL_PERCENT).floor2(ROUND)
      debug("Price is: #{price}")
      debug("Calculating quantity: #{balance1} * #{price}")
      qty      = balance1.floor2(ROUND)
      debug("Quantity is: #{qty}")
      order_id = limit_order("SELL",qty,price)
      return(order_id)
    end
  end
end

def stop_order(order_id)
  # INPUT:  INTEGER, Order ID
  # OUTPUT: BOOL
  debug("Checking if stop price has been reached.")
  price      = get_order_price(order_id).to_f.floor2(ROUND)
  debug("Calculating stop price.")
  stop_price = (price * STOP_PERCENT).to_f.floor2(ROUND)
  debug("Stop price is: #{stop_price}")
  ticker     = get_ticker().to_f.floor2(ROUND)
  debug("Checking if ticker price is less than stop price: #{ticker} <= #{stop_price}")
  if(ticker <= stop_price)
    debug("True")
    debug("Initiating Market-Stop order.")
    cancel_order(order_id)
    qty = get_balance()[0].to_f.floor2(ROUND)
    market_order("sell",qty)
    debug("Initiating stop wait time.")
    wait(STOP_WAIT)
    return(false)
  else
    debug("False")
    return(true)
  end
end

def check_filled(order_id,side)
  # INPUT:  INTEGER, STRING,  Order ID and buy/sell
  status = check_order_status(order_id)
  if(status == "FILLED")
    return(true)
  else
    bbands = calc_bbands(get_candles())
    mband  = bbands[0].to_f.floor2(ROUND)
    uband  = bbands[1].to_f.floor2(ROUND)
    lband  = bbands[2].to_f.floor2(ROUND)
    price  = get_order_price(order_id).to_f.floor2(ROUND)
    if(side == "buy")
      if(lband == price)
        check_filled(order_id,side)
      else
        cancel_order(order_id)
        return(false)
      end
    elsif(side == "sell")
      if(stop_order(order_id))
        return(true)
      elsif(mband == price)
        check_filled(order_id,side)
      else
        cancel_order(order_id)
        return(false)
      end
    end
  end
end

def algo_bb1(side)
  # INPUT:  STRING, buy/sell
  # OUTPUT: NONE
  order_id = trade(side)
  if(check_filled(order_id,side))
    if(side == "buy")
      algo_bb1("sell")
    elsif(side == "sell")
      algo_bb1("buy")
    end
  else
    algo_bb1(side)
  end
end

def ask_side()
  # INPUT:  Buy or Sell
  # OUTPUT: Buy or Sell
  puts ""
  puts ""
  puts "###########################"
  puts "### Choose: BUY or SELL ###"
  puts "###########################"
  puts ""
  puts "1) => BUY"
  puts ""
  puts "2) => SELL"
  puts ""
  puts ""
  print "> "
  input = gets.chomp
  if(input == "1" or input == "2")
    if(input == "1")
      return("buy")
    elsif(input == "2")
      return("sell")
    end
  else
    ask_side()
  end
end
def main()
  # INPUT:  NONE
  # OUTPUT: NONE
  keys           = decrypt()
  debug("Getting API Key")
  api_key        = keys[0]
  debug("Getting Secret Key")
  secret_key     = keys[1]
  debug("Getting Sender Email")
  sender_email   = keys[2]
  debug("Getting Email Password")
  email_password = keys[3]
  debug("Getting Destination Email(s)")
  dest_emails    = keys[4]
  debug("Loading API Key")
  Binance::Api::Configuration.api_key    = api_key
  debug("Loading Secret Key")
  Binance::Api::Configuration.secret_key = secret_key
  algo_bb1(ask_side())
end

main()
