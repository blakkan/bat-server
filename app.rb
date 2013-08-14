require 'sinatra'
require 'pg'
require 'active_record'
require 'sinatra/activerecord'
require 'haml'
require 'json'


################################################################
#
# And here are the database classes for persisting data
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
# Here is where we do our setups 
#
############################################################


configure do 
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
#########################################################
#
# Here are the routes and controllers
#
#########################################################

#
# These controllers return the inventory
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


get '/ledger' do
  
  haml :template_for_ledger
end

#
# These controllers drive the actions; should probably put transactions
# around the various table manipulations
#


get '/buy/:species' do
  if ( Transaction.sum(:dollars) >= Log::COST)
    ActiveRecord::Base.transaction do
      Log.create(:species => params[:species])
      Transaction.create(:dollars => -Log.COST)  #each log costs $20.00
    end
    redirect '/logs'
  else
    @errorMessage = "Attempt to buy a log (cost = $#{Log::COST}) when cash available = $#{Transaction.sum(:dollars)}"
    haml :template_for_fail
  end
end



get '/cut/:logId/:length' do

  begin
    if (theLog = Log.find(params[:logId].to_s.to_i)).consumed == true
      @errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) which has already been cut"
      haml :template_for_fail
    else
      #should probably put a transaction around these
      ActiveRecord::Base.transaction do
        theLog.update( :consumed => true )
        #Get a random number of blanks from each log
        (Random.rand(4)+2).times do
          theLog.blanks.create(:length => params[:length])
        end
        redirect '/blanks'
      end
    end

  rescue ActiveRecord::RecordNotFound
    @errorMessage = "Attempt to cut a log (id = #{params[:logId].to_s}) for which there is no record"
    haml :template_for_fail
  end
end

get '/turn/:blankId/:league' do
  begin
    if Blank.find(params[:blankId].to_s.to_i).consumed == true
      @errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) which has already been turned"
      haml :template_for_fail
    else
      ActiveRecord::Base.transaction do
        Blank.update(params[:blankId].to_s.to_i, :consumed => true )
        Blank.find(params[:blankId].to_s).create_turning(:league => params[:league])
      end
      redirect '/turnings'
    end
  rescue ActiveRecord::RecordNotFound
    @errorMessage = "Attempt to turn a blank (id = #{params[:blankId].to_s}) for which there is no record"
    haml :template_for_fail
  end
end

get '/finish/:turningId/:model' do
  begin
    if Turning.find(params[:turningId].to_s.to_i).consumed == true
      @errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) which has already been turned"
      haml :template_for_fail
    else
      ActiveRecord::Base.transaction do
        Turning.update(params[:turningId].to_s.to_i, :consumed => true )
        Turning.find(params[:turningId].to_s.to_i).create_bat(:model => params[:model])
      end
      redirect '/bats'
    end
  rescue ActiveRecord::RecordNotFound
    @errorMessage = "Attempt to finish a turning (id = #{params[:turningId].to_s}) for which there is no record"
    haml :template_for_fail
  end
end

get '/sell/:batId' do
  begin
    if Bat.find(params[:batId].to_s.to_i).consumed == true
      @errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) which has already been sold"
      haml :template_for_fail
    else
      ActiveRecord::Base.transaction do
        Bat.update(params[:batId].to_s.to_i, :consumed => true )
        Transaction.create(:dollars => Bat::PRICE)  #sell each bat for $10.00
      end
      redirect '/bats'
    end
  rescue ActiveRecord::RecordNotFound
    @errorMessage = "Attempt to sell a bat (id = #{params[:batId].to_s}) for which there is no record"
    haml :template_for_fail
  end
end

#
#  This is where the SOA portion will be
#

def returnPacketHelper

[ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
  :cash => sprintf("$%.2f", Transaction.sum('dollars')),
  :logs => Log.select(:id, :species).where("not consumed").count.to_s,
  :blanks => Blank.select(:id, :length).where("not consumed").count.to_s,
  :turnings => Turning.select(:id, :league).where("not consumed").count.to_s,
  :bats => Bat.select(:id, :model).where("not consumed").count.to_s
  }.to_json ]
end


put '/command' do

  #this is where we'll read the json and decide what to do
  #if we recognize the command.  There is, by design (since this is SOA) no
  #parameter checking.   Unlike human users, we expect the app to get it right.
  #the only thing we check for is command validity (which lets us implement
  #future changes- we can tell versions apart by which commands are recognized)
  theCommandHash = JSON.parse(request.body.read)
  
  case theCommandHash["command"].downcase.gsub(/\s+/, "")
    
    when "summary"
      returnPacketHelper()
    
    when "buy"

    #clone of buy, for now.   Eventually move to subroutine.

    ActiveRecord::Base.transaction do
      Log.create(:species => theCommandHash["species"])
      Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
    end
    returnPacketHelper()

    
  when "cut"
    
    begin
      ActiveRecord::Base.transaction do
        (local = Log.where("not consumed").first!).update(:consumed => true )
        #Get a random number of blanks from each log
        (Random.rand(4)+2).times do
          local.blanks.create(:length => theCommandHash["length"])
        end
      end
      retVal = returnPacketHelper()
    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to cut a log when none are available."]]
    end
    retVal
  
  
  when "turn"
      begin
      ActiveRecord::Base.transaction do
        (local = Blank.where("not consumed").first!).update(:consumed => true )
        local.create_turning(:league => theCommandHash["league"])
      end
        retVal = returnPacketHelper()
      rescue ActiveRecord::RecordNotFound
        retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to turn a blank when none are available."]]
      end
      retVal
    
  
  when "finish"
    begin
      ActiveRecord::Base.transaction do
        (local = Turning.where("not consumed").first!).update(:consumed => true )
        local.create_bat(:model => theCommandHash["model"])
      end
      retVal = returnPacketHelper()
    rescue ActiveRecord::RecordNotFound
      retVal = [404, { 'Content-type' => 'text/plain'}, ["Request to finish a turning when none are available."]]
    end
    retVal
    
  
  when "sell"
    begin
      ActiveRecord::Base.transaction do
        Bat.where("not consumed").first!.update(:consumed => true )
        Transaction.create(:dollars => Bat::PRICE)  #sell each bat for $10.00
      end
      retVal = returnPacketHelper()
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

# basic SOA status return (just in response to a request, not from doing a command)
# this one gives lists of inventories
get '/inventory/json' do
  # could make the type text/json to really do it up right, but for this, just test
  [ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
    :cash => sprintf("$%.2f", Transaction.sum('dollars')),
    :logs => Log.select(:id, :species).where("not consumed").order("id ASC"),
    :blanks => Blank.select(:id, :length).where("not consumed").order("id ASC"),
    :turnings => Turning.select(:id, :league).where("not consumed").order("id ASC"),
    :bats => Bat.select(:id, :model).where("not consumed").order("id ASC")
    }.to_json ]
end

__END__

######################################################
#
# And Sinatra's inline views are right here
#
######################################################


@@template_for_list
%h1= @headText
%h3= "Start of List"
%table
  %tbody
    - @items.each do |row|
      %tr
        %td= row.linelist
%h3= "End of list"

@@template_for_ledger
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
%h1= "Cash Balance = $" + sprintf('%.2f',@total)

@@template_for_ack
%h3= "Completed"

@@template_for_fail
%h3= "Error: " + @errorMessage
