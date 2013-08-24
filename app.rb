require 'sinatra'
require 'pg'
require 'active_record'
require 'sinatra/activerecord'
require 'haml'
require 'json'

#
# Exercise program; intentionally one big file (would normally
# split out all the views and models).    First part of the
# file are the models.   Second, the controller(s), and the final
# part of the file are HAML page definitions.
#
# Since this is fundamentally for SOA use, there isn't any
# css; just a circa 1993 look, if accessed by browsers.
#


################################################################
#
# Here are the database classes for persisting data.
#   Each has a "linelist" method (which is really just an application
#   specific "to string")
#
################################################################
class Transaction < ActiveRecord::Base
  def linelist
    "#{self.id} = #{self.dollars} (Postive is cash receipt, negative is disbursement)"
  end 
end

class Log < ActiveRecord::Base
  
  COST = 20.00
  
  has_many :blanks
  def linelist
    "#{self.id} = #{self.species}, consumed = #{self.consumed.to_s}"
  end

  def list
    [self.id.to_s, self.species, self.consumed.to_s]
  end
end

class Blank < ActiveRecord::Base
  belongs_to :log
  has_one :turning
  def linelist
    "#{self.id} = #{self.log.species}, #{self.length.to_s}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.length.to_s, self.consumed.to_s]
  end
end

class Turning < ActiveRecord::Base
  belongs_to :blank
  has_one :bat
  def linelist
    "#{self.id} = #{self.blank.log.species}, #{self.blank.length}, #{self.league}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.league, self.consumed.to_s]
  end
end

class Bat < ActiveRecord::Base
  
  PRICE = 10.00
  
  belongs_to :turning
  def linelist
    "#{self.id} = #{self.turning.blank.log.species}, #{self.turning.blank.length}, #{self.turning.league}, #{self.model}, consumed = #{self.consumed.to_s}"
  end
  def list
    [self.id.to_s, self.model, self.consumed.to_s]
  end
end

############################################################
#
# Here is the "controller" portion of MVC.    Sinatra has
# a configure section, run at startup.   Then the routes
# and the actions
#
############################################################

#
# Controller setup
#
#  All we do here is do a runtime setup of the global version
# string (left as a variable during testing, (lets us use the
# page title as a "mini-flash" display) would ultimately become
# a constant), and make the database connection.    (Database is
# always postgres, either running locally or on heroku)
#

configure do 
  
  $versionString = "Version 0.1"
  
  ############################################################
  #
  # Hook up the database.   Here we're using a local file, but
  # we could easily change this to hook up to heroku
  #
  # We'll use active record to wrap this stuff for our models
  #
  ############################################################

  #This line is the magic for Heroku; heroku will give us a URL in the
  # environment variable.  But if we don't get that environment variable,
  # then we're running locally (it would seem...)
  db = URI.parse(ENV['DATABASE_URL'] || 'postgres://basic:basic@localhost/factorydb')

  ActiveRecord::Base.establish_connection(
    :adapter  => db.scheme == 'postgres' ? 'postgresql' : db.scheme,
    :host     => db.host,
    :username => db.user,
    :password => db.password,
    :database => db.path[1..-1],
    :encoding => 'utf8'
  )

end

before do
  cache_control  :no_cache
end


#
#
# Here are the routes and controllers
#
#


get '/' do    #default entry
  redirect '/webform'
end


#
# These routes return the inventory of each object, in simple HTML
#



get '/cash_transactions' do
  @items = Transaction.all.to_a
  @headText = "Cash Transactions"
  haml :template_for_list  
end

get '/cash_balance' do
  @total = Transaction.sum('dollars')
  haml :template_for_cash_balance
end

get '/logs' do
  @items = Log.all.to_a
  @headText = "Log Record"
  haml :template_for_list
end

get '/blanks' do
  @items = Blank.all.to_a
  @headText = "Blanks Record"
  haml :template_for_list
end

get '/turnings' do
  @items = Turning.all.to_a
  @headText = "Turnings Record"
  haml :template_for_list
end

get '/bats' do
  @items = Bat.all.to_a
  @headText = "Bats now in stock"
  haml :template_for_list
end

# This route returns an inventory of all the objects, in simple HTML
get '/ledger' do
  haml :template_for_ledger
end

#
# These controllers drive the actions; should probably put transactions
# around the various table manipulations
#


post '/buy/:species' do
  if ( Transaction.sum(:dollars) >= Log::COST)
    ActiveRecord::Base.transaction do
      Log.create(:species => params[:species])
      Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
    end
    #redirect '/logs'
    returnPacketHelper()
  else
    [404, { 'Content-type' => 'text/plain'},["Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"]]
    #@errorMessage = "Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"
    #haml :template_for_fail
  end
end



post '/cut/:logId/:length' do

  begin
    if ( params[:logId].downcase == "oldest")    
      params[:logId] = Log.where("not consumed").first!.id.to_s
    end
    ActiveRecord::Base.transaction do
      if (theLog = Log.find(params[:logId].to_s.to_i)).consumed == true
        @errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) which has already been cut"
        haml :template_for_fail
      else
        theLog.update( :consumed => true )
        #Get a random number of blanks from each log
        (Random.rand(4)+2).times do
          theLog.blanks.create(:length => params[:length])
        end
        #redirect '/blanks'
        returnPacketHelper()
      end
    end

  rescue ActiveRecord::RecordNotFound
    retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to cut a log when none are available."]]
    #@errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) for which there is no record"
    #haml :template_for_fail
  end
end

post '/turn/:blankId/:league' do
  begin
    if ( params[:blankId].downcase == "oldest")    
      params[:blankId] = Blank.where("not consumed").first!.id.to_s  
    end
    ActiveRecord::Base.transaction do
      if Blank.find(params[:blankId].to_s.to_i).consumed == true
        @errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) which has already been turned"
        haml :template_for_fail
      else
        Blank.update(params[:blankId].to_s.to_i, :consumed => true )
        Blank.find(params[:blankId].to_s).create_turning(:league => params[:league])
      end
      #redirect '/turnings'
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to turn a blank when none are available."]]
    #@errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) for which there is no record"
    #haml :template_for_fail
  end
end

post '/finish/:turningId/:model' do
  begin
    if ( params[:turningId].downcase == "oldest")    
      params[:turningId] = Turning.where("not consumed").first!.id.to_s
    end
    
    ActiveRecord::Base.transaction do
      if Turning.find(params[:turningId].to_s.to_i).consumed == true
        @errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) which has already been turned"
        haml :template_for_fail
      else
        Turning.update(params[:turningId].to_s.to_i, :consumed => true )
        Turning.find(params[:turningId].to_s.to_i).create_bat(:model => params[:model])
      end
      #redirect '/bats'
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    [404, { 'Content-type' => 'text/plain'}, ["Request to finish a turning when none are available."]]
    #@errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) for which there is no record"
    #haml :template_for_fail
  end
end

post '/sell/:batId' do
  begin
    if ( params[:batId].downcase == "oldest")    
      params[:batId] = Bat.where("not consumed").first!.id.to_s
    end
  
    ActiveRecord::Base.transaction do
      if Bat.find(params[:batId].to_s.to_i).consumed == true
        @errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) which has already been sold"
        haml :template_for_fail
      else
        Bat.update(params[:batId].to_s.to_i, :consumed => true )
        Transaction.create(:dollars => Bat::PRICE)  #sell each bat for $10.00
      end
      #redirect '/bats'
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    [404, { 'Content-type' => 'text/plain'}, ["Request to sell a bat when none are available."]]
    ##@errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) for which there is no record"
    ##haml :template_for_fail
  end
end

#
#  This is where the SOA portion will be
#

def returnPacketHelper
  retVal = [ 500, { 'Content-type' => 'text/plain'}, ["Return Packet Helper Failed"]]
  ActiveRecord::Base.transaction do   #read only but still wrap with a transaction

    retVal = [ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
      :cash => sprintf("$%.2f", Transaction.sum('dollars')),
      :logs => Log.select(:id, :species).where("not consumed").count.to_s,
      :blanks => Blank.select(:id, :length).where("not consumed").count.to_s,
      :turnings => Turning.select(:id, :league).where("not consumed").count.to_s,
      :bats => Bat.select(:id, :model).where("not consumed").count.to_s
      }.to_json ]
  end
  retVal
end


#
# This version is less "RESTful"- kind of SOAPy, but with JSON -
# it takes a command from a post, but the command is in the data,
# rather than the URI.
# the more "RESTful" way is to encode the operation into a POST against
# an item.   For pedegogical purposes, these operations are mostly cloned;
# for production, we'd put much of the operation into shared helper methods.
#

post '/command' do

  #this is where we'll read the json and decide what to do
  #if we recognize the command.  There is, by design (since this is SOA) no
  #parameter checking.   Unlike human users, we expect the app to get it right.
  #the only thing we check for is command validity (which lets us implement
  #future changes- we can tell versions apart by which commands are recognized)
  theCommandHash = JSON.parse(request.body.read)
  
  retVal = [ 500, { 'Content-type' => 'text/plain'}, ["JSON inventory failed"]]   #Just to make visible, and we leave it at this to handle error cases
  
  case theCommandHash["command"].downcase.gsub(/\s+/, "")

  when "summary"
    returnPacketHelper()

  when "buy"

    #clone of buy, for now.   Eventually move to subroutine.

    ActiveRecord::Base.transaction do

      if ( Transaction.sum(:dollars) >= Log::COST )
        Log.create(:species => theCommandHash["species"])
        Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
        retVal = returnPacketHelper()
      else
        retVal = [404, { 'Content-type' => 'text/plain'},["Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"]]
      end #end of if

    end #end of transaction
    retVal


  when "cut"

    begin
      ActiveRecord::Base.transaction do
        (local = Log.where("not consumed").first!).update(:consumed => true )
        #Get a random number of blanks from each log
        (Random.rand(4)+2).times do
          local.blanks.create(:length => theCommandHash["length"])
          retVal = returnPacketHelper()
        end
      end

    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to cut a log when none are available."]]
    end
    retVal

  when "turn"
    begin
      ActiveRecord::Base.transaction do
        (local = Blank.where("not consumed").first!).update(:consumed => true )
        local.create_turning(:league => theCommandHash["league"])
        retVal = returnPacketHelper()
      end

    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to turn a blank when none are available."]]
    end
    retVal

  when "finish"
    begin
      ActiveRecord::Base.transaction do
        (local = Turning.where("not consumed").first!).update(:consumed => true )
        local.create_bat(:model => theCommandHash["model"])
        retVal = returnPacketHelper()
      end

    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to finish a turning when none are available."]]
    end
    retVal

  when "sell"
    begin
      ActiveRecord::Base.transaction do
        Bat.where("not consumed").first!.update(:consumed => true )
        Transaction.create(:dollars => Bat::PRICE)  #sell each bat for $10.00
        retVal = returnPacketHelper()
      end

    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to sell a bat when none are available."]]
    end
    retVal

  else

    [ 400, { 'Content-type' => 'text/plain'}, ["Unrecognized command"]]

  end
end




#
# basic SOA status return (just in response to a request, not from doing a command)
#

get '/summary/json' do
  returnPacketHelper()

end

#
# basic SOA status return (just in response to a request, not from doing a command)
# this one gives lists of inventories in json format
#
get '/inventory/json' do

  retVal = [ 500, { 'Content-type' => 'text/plain'}, ["JSON inventory failed"]] 
  ActiveRecord::Base.transaction do
    # could make the type text/json to really do it up right, but for this, just test
    retVal = [ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
      :cash => sprintf("$%.2f", Transaction.sum('dollars')),
      :logs => Log.select(:id, :species).where("not consumed").order("id ASC"),
      :blanks => Blank.select(:id, :length).where("not consumed").order("id ASC"),
      :turnings => Turning.select(:id, :league).where("not consumed").order("id ASC"),
      :bats => Bat.select(:id, :model).where("not consumed").order("id ASC")
      }.to_json ]
  end
  retVal
end

#
# Basic operations from the web; this is more for user interaction on the
# web, rather than a RESTful SOA API.
#

get '/webform' do   #Gets a page showing buttons for the commands

  @myJSONContent = returnPacketHelper()[2].to_s
  haml :template_for_control_form

end

post '/form_result' do  #Acts on the commands; acts on items fifo order
                        # only; can't "restuflly" access by id; only supports fixed species, length, etc.
  
  retVal = [ 500, { 'Content-type' => 'text/plain'}, ["Unrecognized Operation"]]  #Just to make visible, and we leave it at this to handle error cases

  case params["button_name"].downcase

  # should use ruby case
  when "buy"
    #clone of buy, for now.   Eventually move to subroutine.
    ActiveRecord::Base.transaction do

      if ( Transaction.sum(:dollars) >= Log::COST )
        Log.create(:species => "Ash")
        Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
        @myJSONContent = returnPacketHelper()[2].to_s
        retVal = haml :template_for_control_form
      else
        #retVal = [404, { 'Content-type' => 'text/plain'},["Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"]]
        @errorMessage = "Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"
        retVal = haml :template_for_fail
      end #end of if

    end #end of transaction
    retVal

  when "cut"
    begin
      ActiveRecord::Base.transaction do
        (local = Log.where("not consumed").first!).update(:consumed => true )
        #Get a random number of blanks from each log
        (Random.rand(4)+2).times do
          local.blanks.create(:length => 38)
        end
        @myJSONContent = returnPacketHelper()[2].to_s
        retVal = haml :template_for_control_form
      end

    rescue ActiveRecord::RecordNotFound
      #retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to cut a log when none are available."]]
      @errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) for which there is no record"
      retVal = haml :template_for_fail
    end
    retVal

  when "turn"
    begin
      ActiveRecord::Base.transaction do
        (local = Blank.where("not consumed").first!).update(:consumed => true )
        local.create_turning(:league => "AL")
        @myJSONContent = returnPacketHelper()[2].to_s
        retVal = haml :template_for_control_form
      end

    rescue ActiveRecord::RecordNotFound
      #retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to turn a blank when none are available."]]
      @errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) for which there is no record"
      retVal = haml :template_for_fail
    end
    retVal

  when "finish"
    begin
      ActiveRecord::Base.transaction do
        (local = Turning.where("not consumed").first!).update(:consumed => true )
        local.create_bat(:model => "Cobb")
        @myJSONContent = returnPacketHelper()[2].to_s
        retVal = haml :template_for_control_form
      end
      
    rescue ActiveRecord::RecordNotFound
      #[404, { 'Content-type' => 'text/plain'}, ["Request to finish a turning when none are available."]]
      @errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) for which there is no record"
      retVal = haml :template_for_fail
    end
    retVal
    
  when "sell"
    begin
      ActiveRecord::Base.transaction do
        Bat.where("not consumed").first!.update(:consumed => true )
        Transaction.create(:dollars => Bat::PRICE)  #sell each bat for $10.00
        @myJSONContent = returnPacketHelper()[2].to_s
        retVal = haml :template_for_control_form
      end
    rescue ActiveRecord::RecordNotFound
      #retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to sell a bat when none are available."]]
      @errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) for which there is no record"
      retVal = haml :template_for_fail
    end
    retVal
   
  when "update screen"
    @myJSONContent = returnPacketHelper()[2].to_s
    haml :template_for_control_form

  else
    [ 400, { 'Content-type' => 'text/plain'}, ["Unrecognized command"]]
  end

end


__END__



######################################################
#
# Sinatra's inline views are right here
#
######################################################

@@soa_ack
%head
  %title= $versionString
  %cash
%body= "ACK"

@@template_for_list
%head
  %title= $versionString
  %cash
%body
  %h1= @headText
  %h3= "Start of List"
  %table
    %tbody
      - @items.each do |row|
        %tr
          %td= row.linelist
  %h3= "End of list"

@@template_for_ledger
%head
  %title= $versionString
%body
  %h1= "Ledger of all tables"
  %h2= "Cash"
  %table{"border"=>"1"}
    %th= "ID"
    %th= "Receipt"
    -Transaction.all.order("id ASC").each do |row|
      %tr
        %td= row.id
        %td= sprintf("$%.2f",row.dollars)
  %h2= "Logs"
  %table{"border"=>"1"}
    %th= "Log ID"
    %th= "Species"
    %th= "Consumed?"
    -Log.all.order("id ASC").each do |row|
      %tr
        %td= row.id
        %td= row.species
        %td= row.consumed
  %h2= "Blanks"
  %table{"border"=>"1"}
    %th= "Blank ID"
    %th= "From Log ID"
    %th= "Length"
    %th= "Consumed?"
    -Blank.all.order("id ASC").each do |row|
      %tr
        %td= row.id
        %td= row.log_id
        %td= row.length
        %td= row.consumed
  %h2= "Turnings"
  %table{"border"=>"1"}
    %th= "Turning ID"
    %th= "From Blank ID"
    %th= "League"
    %th= "Consumed?"
    -Turning.all.order("id ASC").each do |row|
      %tr
        %td= row.id
        %td= row.blank_id
        %td= row.league
        %td= row.consumed
  %h2= "Bats"
  %table{"border"=>"1"}
    %th= "Bat ID"
    %th= "From Turning ID"
    %th= "Model"
    %th= "Sold?"
    -Bat.all.order("id ASC").each do |row|
      %tr
        %td= row.id
        %td= row.turning_id
        %td= row.model
        %td= row.consumed


@@template_for_cash_balance
%head
  %title= $versionString
%body
  %h1= "Cash Balance = $" + sprintf('%.2f',@total)

@@template_for_ack
%head
  %title= $versionString
%body
  %h3= "Completed"

@@template_for_fail
%head
  %title= $versionString
%body
  %h3= "Error: " + @errorMessage
  
@@template_for_control_form
%head
  %title= $versionString
%body
  %h1= "Summary Ledger (JSON format)"
  %h3= @myJSONContent
  %h1= "Select an operation"
  %form{:method => "post", :action => "/form_result", :name => "my_input" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Buy" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Cut" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Turn" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Finish" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Sell" }
    %input{:type => "submit", :class => "button", :name=>"button_name", :value=>"Update Screen" }

