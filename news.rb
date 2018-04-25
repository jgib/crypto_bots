#!/usr/bin/env ruby
require 'pp'
require 'json'
require 'date'
require 'gmail'
require 'mechanize'
require 'io/console'

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

def get_timestamp()
  # INPUT:  NONE
  # OUTPUT: Timestamp in format TIME ::: EPOCH
  time  = Time.now.to_s
  epoch = Time.now.to_f.round(4)
  return("#{time}:#{epoch}")
end

def debug(text)
  # INPUT:  STRING
  # OUTPUT: Displays string input prepended with timestamp if DEBUG is set to true in config.
  if DEBUG == true
    parent = caller_locations[0].label.to_s
    time   = get_timestamp
    STDERR.puts("#{time}:#{parent}:#{text}")
  end
end

def wait(seconds)
  # INPUT:  INTEGER or FLOAT
  # OUTPUT: NONE
  debug("Waiting #{seconds} seconds...  [Approx. #{(seconds / 60).round(3)} Mins]")
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

def mail(title.to_s,message.to_s)
  $dest_emails.each do |send_to|
    debug("Preparing to send email to #{send_to}")
    debug("Logged in to #{$sender_email}")
    gmail = Gmail.connect($sender_email,$email_password)
    email = gmail.compose do
      to      send_to
      subject title
      body    message
    end
    debug("Sending email")
    gmail.deliver(email)
    debug("Logging out")
    gmail.logout
  end
end


