
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
  #
  # My one, disgraceful, global variable.   And not even a constant.
  #
  # Why?   Why?    Well, I display it as the title of webpages, and
  # this gives the option (during development only!) of altering
  # page titles on the fly.   Using it as a pseuld "Flash" (or Toast,
  # in Android parlance.
  #
  $versionString = "Version 0.1a"
  
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
  # then we're running locally (it would seem...) so we just hook up to
  # the local DB.    Others might use SQLite for the local database.
  # But postgres is not much harder to use, and it's what'll be used
  # on Heroku anyway, so why not use it locally?
  
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

# before, unlike configure, is run at the start of each request
before do
  cache_control  :no_cache
end


###############################################################################
#
#
# Here are the routes and controllers.   This is the nature of Sinatra
# vs. Rails.   Sinatra is just a simple DSL, built on top of the rack
# middleware.  So it's parsing out the verb, and coming in with a CALL, and
# matching the verb and sting patterns below.
#
#
##############################################################################

get '/' do    #default entry; just redirect
  redirect '/webform'
end



######################################################################
#
#
# These routes return the inventory of each object, in simple HTML
#
# These are just building-block utility pages, mostly for debug,
# since they're just a subset of the "general ledger"
#
#####################################################################


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

###########################################################################
#
#
# These URLs are the RESTful entry points used by the Android version
#
#   Note that when android calls this as a "Service Oriented Architecture,
# we return JSON strings, not HTML for a brower to render.
#
#   Note also that there are transaction block surrounding the modification
# of the tables.
#
#   In what may not be quite as RESTful as one might like, if the Android
# application requests the use of a resource that doesn't exist, we don't
# throw an HTTP 404.   We throw the 200, but send a non-empty string with
# an error or warning.   In a sense, this is still RESTful, if we consider
# that a "consumed" resource actually still exists as an accounting record...
#
#  If this were production code, the messages would be removed to a file
# for constants (to permit easy internationalization, etc.).   The design decision here
# is that error messages associated with the tables themselves will be provided by
# the server, rather than android.   It doesn't have to be this way, but it does
# let us change/add error messages (or internationaize) without updating android
# apps in the field.
#
###########################################################################

post '/buy/:species' do
  if ( Transaction.sum(:dollars) >= Log::COST)
    ActiveRecord::Base.transaction do
      Log.create(:species => params[:species])
      Transaction.create(:dollars => -Log::COST)  #each log costs $20.00
    end
    returnPacketHelper()
  else
    returnPacketHelper( "Attempt to buy a log (cost = #{sprintf("$%.2f", Log::COST)}) when cash available = #{sprintf("$%.2f", Transaction.sum(:dollars))}" )
  end
end


post '/cut/:logId/:length' do
  begin
    if ( params[:logId].downcase == "oldest")                    # rather than an index, the Antroid app
      params[:logId] = Log.where("not consumed").first!.id.to_s  #  usually just asks for the lowest sequenced one.
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

        returnPacketHelper()
      end
    end

  rescue ActiveRecord::RecordNotFound
    returnPacketHelper("Request to cut a log when none are available.")
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
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    returnPacketHelper("Request to turn a blank when none are available.")
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
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    returnPacketHelper("Request to finish a turning when none are available.")
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
      returnPacketHelper()
    end
  rescue ActiveRecord::RecordNotFound
    returnPacketHelper("Request to sell a bat when none are available.")
  end
end

#
# Here's the helper method we've been using in all the RESTful routes.
#  It just packages up a summary of the table status; along with any optional error message.
#  This is the basic JSON packet returned to Android as a response.
#
def returnPacketHelper( toastMessageString = "" )
  # This next line is just a bit of defensive programming; something to return
  # if the database access (read only) happens to throw some weird, unanticipated
  # exception, or otherwise not work, at least we won't be returning null.
  retVal = [ 500, { 'Content-type' => 'text/plain'}, ["Return Packet Helper Failed"]]
    
    
  ActiveRecord::Base.transaction do   #read only but still wrap with a transaction
    retVal = [ 200, { 'Content-type' => 'application/json', 'Cache-control' => 'no-cache'}, {
      :cash => sprintf("$%.2f", Transaction.sum('dollars')),
      :logs => Log.select(:id, :species).where("not consumed").count.to_s,
      :blanks => Blank.select(:id, :length).where("not consumed").count.to_s,
      :turnings => Turning.select(:id, :league).where("not consumed").count.to_s,
      :bats => Bat.select(:id, :model).where("not consumed").count.to_s,
      :message => toastMessageString
      }.to_json ]
  end
  retVal
end


#########################################################################
#
# What follows is actually dead code, currently.
#
#
# This version is less "RESTful"- kind of SOAPy, but with JSON -
# it takes a command from a post, but the command is in the data,
# rather than the URI.  The more "RESTful" way is to encode the operation into a POST against
# an item.   For pedegogical purposes, these operations are mostly cloned;
# for production, we'd put much of the operation into shared helper methods.
#
#########################################################################


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
        retVal = [404, { 'Content-type' => 'text/plain'},["Attempt to buy a log (cost = #{sprintf("$%.2f",Log::COST)} when cash available = #{sprintf("$%.2f",Transaction.sum(:dollars))}"]]
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


######################################################################################
#
# basic SOA status return (just in response to a request, not from doing a command)
#
# Anybody can request this; Android or a website, as long as they're happy to get
# JSON rather than HTML.   It returns summary quantities
#
######################################################################################

get '/summary/json' do
  returnPacketHelper()
end

######################################################################################
#
# basic SOA status return (just in response to a request, not from doing a command)
# this one gives lists of inventories in json format.  (So this gives table contents,
# not just table column summaries)
#
#####################################################################################

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

#############################################################################
#
# Basic operations from the web; this is more for user interaction on the
# web, rather than a RESTful SOA API.
#
# Consists of the usual two webpages;  One a form, and the other a form
# response.
#
# Pieces of this (and the RESTful command versions) would eventually
# migrage to helper methods.
#
#############################################################################

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
        @errorMessage = "Attempt to buy a log (cost = #{sprintf("$%.2f",Log::COST)}) when cash available = #{sprintf("$%.2f",Transaction.sum(:dollars))}"
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
      @errorMessage = "Attempt to cut a log for which there is no record"
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
      @errorMessage = "Attempt to turn a blank for which there is no record"
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
      @errorMessage = "Attempt to finish a turning for which there is no record"
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
      @errorMessage = "Attempt to sell a bat for which there is no record"
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


