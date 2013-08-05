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

#
# These controllers drive the actions; should probably put transactions
# around the various table manipulations
#


get '/buy/:species' do
  if ( Transaction.sum(:dollars) >= Log::COST)
    Log.create(:species => params[:species])
    Transaction.create(:dollars => -Log.COST)  #each log costs $20.00
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

put '/command' do

  #this is where we'll read the json and decide what to do
  #if we recognize the command
  theCommandHash = JSON.parse(request.body.read)
  
  if theCommandHash["command"] =~ /BUY/i

    #clone of buy, for now.   Eventually move to subroutine.
    ActiveRecord::Base.transaction do
      Log.create(:species => params[:species])
      Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
    end
    redirect '/inventory/json'

  else

    [ 200, { 'Content-type' => 'text/plain'}, [request.body.read]]

  end
end

# basic SOA status return (just in response to a request, not from doing a command)
get '/summary/json' do
  # could make the type text/json to really do it up right, but for this, just test
  [ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
    :cash => sprintf("$%.2f", Transaction.sum('dollars')),
    :logs => Log.select("not consumed").count.to_s,
    :blanks => Blank.select("not consumed").count.to_s,
    :turnings => Turning.select("not consumed").count.to_s,
    :bats => Bat.select("not consumed").count.to_s
    }.to_json ]
end

# basic SOA status return (just in response to a request, not from doing a command)
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

@@template_for_cash_balance
%h1= "Cash Balance = $" + sprintf('%.2f',@total)

@@template_for_ack
%h3= "Completed"

@@template_for_fail
%h3= "Error: " + @errorMessage
