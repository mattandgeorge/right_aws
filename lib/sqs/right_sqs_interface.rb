#
# Copyright (c) 2007 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

module RightAws

  class SqsInterface
    
    SIGNATURE_VERSION = "1"
    API_VERSION       = "2007-05-01"
    DEFAULT_HOST      = "queue.amazonaws.com"
    DEFAULT_PORT      = 443
    DEFAULT_PROTOCOL  = 'https'
    REQUEST_TTL       = 30
    DEFAULT_VISIBILITY_TIMEOUT = 30
      # A list if Amazons problems we can handle by AWSErrorHandler.
    @@amazon_problems = RightAws::AMAZON_PROBLEMS

      # Current aws_access_key_id
    attr_reader :aws_access_key_id
      # Last HTTP request object
    attr_reader :last_request
      # Last HTTP response object
    attr_reader :last_response
      # Last AWS errors list (used by AWSErrorHandler)
    attr_accessor :last_errors
      # Last AWS request id (used by AWSErrorHandler)
    attr_accessor :last_request_id
      # Logger object
    attr_accessor :logger
      # Initial params hash
    attr_accessor :params
    
    @@bench_sqs = Benchmark::Tms.new()
    @@bench_xml = Benchmark::Tms.new()
    
      # Benchmark::Tms instance for SQS access benchmark.
    def self.bench_sqs; @@bench_sqs;  end  
      # Benchmark::Tms instance for XML parsing benchmark.
    def self.bench_xml; @@bench_xml; end  # For benchmark puposes.

      # Returns a list of Amazon service responses which are known as problems on Amazon side. 
      # We have to re-request again if we've got any of them - probably the problem will disappear. By default returns the same value as AMAZON_PROBLEMS const.
    def self.amazon_problems
      @@amazon_problems
    end
    
      # Sets a list of Amazon side problems.
    def self.amazon_problems=(problems_list)
      @@amazon_problems = problems_list
    end

      # Creates new RightSqs instance.
      #
      #  sqs = RightSqs.new('1E3GDYEOGFJPIT75KDT40','hgTHt68JY07JKUY08ftHYtERkjgtfERn57DFE379', {:multi_thread => true, :logger => Logger.new('/tmp/x.log')}) #=> <RightSqs:0xb7af6264>
      #  
      # Params is a hash:
      #
      #    {:server       => 'queue.amazonaws.com' # Amazon service host: 'queue.amazonaws.com'(default)
      #     :port         => 443                   # Amazon service port: 80 or 443(default)
      #     :multi_thread => true|false            # Multi-threaded (connection per each thread): true or false(default)
      #     :logger       => Logger Object}        # Logger instance: logs to STDOUT if omitted }
      #
    def initialize(aws_access_key_id, aws_secret_access_key, params={})
      @params = params
      raise AwsError.new("AWS access keys are required to operate on SQS") \
        if aws_access_key_id.blank? || aws_secret_access_key.blank?
      @aws_access_key_id     = aws_access_key_id
      @aws_secret_access_key = aws_secret_access_key
        # params
      @params[:server]       ||= DEFAULT_HOST
      @params[:port]         ||= DEFAULT_PORT
      @params[:protocol]     ||= DEFAULT_PROTOCOL
      @params[:multi_thread] ||= defined?(AWS_DAEMON)
        # set logger
      @logger = @params[:logger]
      @logger = RAILS_DEFAULT_LOGGER if !@logger && defined?(RAILS_DEFAULT_LOGGER)
      @logger = Logger.new(STDOUT)   if !@logger
      @logger.info "New #{self.class.name} using #{@params[:multi_thread] ? 'multi' : 'single'}-threaded mode"
    end

    def on_exception(options={:raise=>true, :log=>true}) # :nodoc:
      AwsError::on_aws_exception(self, options)
    end

      # Return the +true+ if this RightS3 instance works in multi_thread state and +false+ otherwise.
    def multi_thread
      @params[:multi_thread]
    end

  #-----------------------------------------------------------------
  #      Requests
  #-----------------------------------------------------------------

      # Generates request hash for QUERY API
    def generate_request(action, param={})  # :nodoc:
        # Sometimes we need to use queue uri (delete queue etc)
        # In that case we will use Symbol key: 'param[:queue_url]'
      queue_uri = param[:queue_url] ? URI(param[:queue_url]).path : '/'
        # remove unset(=optional) and symbolyc keys
      param.each{ |key, value| param.delete(key) if (value.nil? || key.is_a?(Symbol)) }
        # prepare output hash
      request_hash = { "Action"           => action,
                       "Expires"          => Time.now.utc.since(REQUEST_TTL).strftime("%Y-%m-%dT%H:%M:%SZ"),
                       "AWSAccessKeyId"   => @aws_access_key_id,
                       "Version"          => API_VERSION,
                       "SignatureVersion" => SIGNATURE_VERSION }
      request_hash.update(param)
      request_data   = request_hash.sort{|a,b| (a[0].to_s.downcase)<=>(b[0].to_s.downcase)}.to_s
      request_hash['Signature'] = Base64.encode64( OpenSSL::HMAC.digest( OpenSSL::Digest::Digest.new( "sha1" ), @aws_secret_access_key, request_data)).strip
      request_params = request_hash.to_a.collect{|key,val| key.to_s + "=" + CGI::escape(val.to_s) }.join("&")
      request        = Net::HTTP::Get.new("#{queue_uri}?#{request_params}")
        # prepare output hash
      { :request  => request, 
        :server   => @params[:server],
        :port     => @params[:port],
        :protocol => @params[:protocol] }
    end

      # Generates request hash for REST API
    def generate_rest_request(method, param) # :nodoc:
      queue_uri = param[:queue_url] ? URI(param[:queue_url]).path : '/'
      message   = param[:message]                # extract message body if nesessary
        # remove unset(=optional) and symbolyc keys
      param.each{ |key, value| param.delete(key) if (value.nil? || key.is_a?(Symbol)) }
        # created request
      param_to_str = param.to_a.collect{|key,val| key.to_s + "=" + CGI::escape(val.to_s) }.join("&")
      param_to_str = "?#{param_to_str}" unless param_to_str.blank?
      request = "Net::HTTP::#{method.titleize}".constantize.new("#{queue_uri}#{param_to_str}")
      request.body = message if message
        # set main headers
      request['content-md5']  = ''
      request['Content-Type'] = 'text/plain'
      request['Date']         = Time.now.httpdate
        # generate authorization string
      auth_string = "#{method.upcase}\n#{request['content-md5']}\n#{request['Content-Type']}\n#{request['Date']}\n#{CGI::unescape(queue_uri)}"
      signature   = Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new("sha1"), @aws_secret_access_key, auth_string)).strip
        # set other headers
      request['Authorization'] = "AWS #{@aws_access_key_id}:#{signature}"
      request['AWS-Version']   = API_VERSION
        # prepare output hash
      { :request  => request, 
        :server   => @params[:server],
        :port     => @params[:port],
        :protocol => @params[:protocol] }
    end


      # Sends request to Amazon and parses the response
      # Raises AwsError if any banana happened
    def request_info(request, parser) # :nodoc:
      thread = @params[:multi_thread] ? Thread.current : Thread.main
      thread[:sqs_connection] ||= Rightscale::HttpConnection.new(:exception => AwsError)
      @last_request  = request[:request]
      @last_response = nil
      response=nil
      
      @@bench_sqs.add!{ response = thread[:sqs_connection].request(request) }
        # check response for errors...
      @last_response = response
      if response.is_a?(Net::HTTPSuccess)
        @error_handler = nil
        @@bench_xml.add! do
          if parser.kind_of?(RightAWSParser)
            REXML::Document.parse_stream(response.body, parser)
          else
            parser.parse(response)
          end
        end
        return parser.result
      else
        @error_handler = AWSErrorHandler.new(self, parser, @@amazon_problems) unless @error_handler
        check_result   = @error_handler.check(request)
        if check_result
          @error_handler = nil
          return check_result 
        end
        raise AwsError.new(@last_errors, @last_response.code, @last_request_id)
      end
    rescue
      @error_handler = nil
      raise
    end


      # Creates new queue. Returns new queue link.
      #
      #  sqs.create_queue('my_awesome_queue') #=> 'http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue'
      #
    def create_queue(queue_name, default_visibility_timeout=nil)
      req_hash = generate_request('CreateQueue', 
                                  'QueueName'                => queue_name,
                                  'DefaultVisibilityTimeout' => default_visibility_timeout || DEFAULT_VISIBILITY_TIMEOUT )
      request_info(req_hash, SqsCreateQueueParser.new)
    end

     # Creates new queue. If +queue_name_prefix+ is omitted then retrieves a list of all queues.
     #
     #  sqs.create_queue('my_awesome_queue')
     #  sqs.create_queue('my_awesome_queue_2')
     #  sqs.list_queues('my_qwesome') #=> ['http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue','http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue_2']
     #
    def list_queues(queue_name_prefix=nil)
      req_hash = generate_request('ListQueues', 'QueueNamePrefix' => queue_name_prefix)
      request_info(req_hash, SqsListQueuesParser.new)
    rescue
      on_exception
    end
      
      # Deletes queue (queue must be empty or +force_deletion+ must be set to true). Queue is identified by url. Returns +true+ or an exception.
      #
      #  sqs.delete_queue('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue_2') #=> true
      #
    def delete_queue(queue_url, force_deletion = false)
      req_hash = generate_request('DeleteQueue', 
                                  'ForceDeletion' => force_deletion.to_s,
                                  :queue_url      => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end

      # Retrieves the queue attribute(s). Returns a hash of attribute(s) or an exception.
      #
      #  sqs.get_queue_attributes('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> {"ApproximateNumberOfMessages"=>"0", "VisibilityTimeout"=>"30"}
      #
    def get_queue_attributes(queue_url, attribute='All')
      req_hash = generate_request('GetQueueAttributes', 
                                  'Attribute' => attribute,
                                  :queue_url  => queue_url)
      request_info(req_hash, SqsGetQueueAttributesParser.new)
    rescue
      on_exception
    end

      # Sets queue attribute. Returns +true+ or an exception.
      #
      #  sqs.set_queue_attributes('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', "VisibilityTimeout", 10) #=> true
      #
      # P.S. Hmm... Amazon returns success even if such attribute does not exist. And they need some seconds to change attribute value.
    def set_queue_attributes(queue_url, attribute, value)
      req_hash = generate_request('SetQueueAttributes', 
                                  'Attribute' => attribute,
                                  'Value'     => value,
                                  :queue_url  => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end

     # Sets visibility timeout. Returns +true+ or an exception.
     #
     #  sqs.set_visibility_timeout('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 15) #=> true
     #
     # See also: +set_queue_attributes+
     #
    def set_visibility_timeout(queue_url, visibility_timeout=nil)
      req_hash = generate_request('SetVisibilityTimeout', 
                                  'VisibilityTimeout' => visibility_timeout || DEFAULT_VISIBILITY_TIMEOUT,
                                  :queue_url => queue_url )
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end

     # Retrieves visibility timeout.
     #
     #  sqs.get_visibility_timeout('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> 15
     #
     # See also: +get_queue_attributes+
     #
    def get_visibility_timeout(queue_url)
      req_hash = generate_request('GetVisibilityTimeout', :queue_url => queue_url )
      request_info(req_hash, SqsGetVisibilityTimeoutParser.new)
    rescue
      on_exception
    end

     # Adds grants for user (identified by email he registered at Amazon). Returns +true+ or an exception. Permission = 'FULLCONTROL' | 'RECEIVEMESSAGE' | 'SENDMESSAGE'.
     #
     #  sqs.add_grant('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 'my_awesome_friend@gmail.com', 'FULLCONTROL') #=> true
     #
    def add_grant(queue_url, grantee_email_address, permission = nil)
      req_hash = generate_request('AddGrant', 
                                  'Grantee.EmailAddress' => grantee_email_address,
                                  'Permission'           => permission,
                                  :queue_url             => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end
    
      # Retrieves hash of +grantee_id+ => +perms+ for this queue:
      #
      #  sqs.list_grants('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=>
      #    {"000000000000000000000001111111111117476c7fea6efb2c3347ac3ab2792a"=>{:name=>"root", :perms=>["FULLCONTROL"]},
      #     "00000000000000000000000111111111111e5828344600fc9e4a784a09e97041"=>{:name=>"myawesomefriend", :perms=>["FULLCONTROL"]}  
      #
    def list_grants(queue_url, grantee_email_address=nil, permission = nil)
      req_hash = generate_request('ListGrants', 
                                  'Grantee.EmailAddress' => grantee_email_address,
                                  'Permission'           => permission,
                                  :queue_url             => queue_url)
      response = request_info(req_hash, SqsListGrantsParser.new)
        # One user may have up to 3 permission records for every queue.
        # We will join these records to one.
      result = {}    
      response.each do |perm|
        id = perm[:id]
          # create hash for new user if unexisit
        result[id] = {:perms=>[]} unless result[id]
          # fill current grantee params
        result[id][:perms] << perm[:permission]
        result[id][:name] = perm[:name]
      end
      result
    end

      # Revokes permission from user. Returns +true+ or an exception.
      #
      #  sqs.remove_grant('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 'my_awesome_friend@gmail.com', 'FULLCONTROL') #=> true
      #
    def remove_grant(queue_url, grantee_email_address_or_id, permission = nil)
      grantee_key = grantee_email_address_or_id.include?('@') ? 'Grantee.EmailAddress' : 'Grantee.ID'
      req_hash = generate_request('RemoveGrant', 
                                  grantee_key  => grantee_email_address_or_id,
                                  'Permission' => permission,
                                  :queue_url   => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end

      # Retrieves a list of messages from queue. Returns an array of hashes in format: <tt>{:id=>'message_id', body=>'message_body'}</tt>
      #
      #   sqs.receive_messages('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue',10, 5) #=>
      #    [{:id=>"12345678904GEZX9746N|0N9ED344VK5Z3SV1DTM0|1RVYH4X3TJ0987654321", :body=>"message_1"}, ..., {}]
      #
      # P.S. Usually returns less messages than have been requested even if they are available.
      #
    def receive_messages(queue_url, number_of_messages=1, visibility_timeout=nil)
      return [] if number_of_messages == 0
      req_hash = generate_rest_request('GET',
                                       'NumberOfMessages'  => number_of_messages,
                                       'VisibilityTimeout' => visibility_timeout,
                                       :queue_url          => "#{queue_url}/front" )
      request_info(req_hash, SqsReceiveMessagesParser.new)
    rescue
      on_exception
    end
    
      # Peeks message from queue by message id. Returns message in format of <tt>{:id=>'message_id', :body=>'message_body'}</tt> or +nil+.
      #
      #  sqs.peek_message('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', '1234567890...0987654321') #=>
      #    {:id=>"12345678904GEZX9746N|0N9ED344VK5Z3SV1DTM0|1RVYH4X3TJ0987654321", :body=>"message_1"}
      #
    def peek_message(queue_url, message_id)
      req_hash = generate_rest_request('GET', :queue_url => "#{queue_url}/#{CGI::escape message_id}" )
      messages = request_info(req_hash, SqsReceiveMessagesParser.new)
      messages.blank? ? nil : messages[0]
    rescue
      on_exception
    end

      # Sends new message to queue.Returns 'message_id' or raises an exception.
      #
      #  sqs.send_message('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 'message_1') #=> "1234567890...0987654321"
      #
    def send_message(queue_url, message)
      req_hash = generate_rest_request('PUT',
                                       :message   => message,
                                       :queue_url => "#{queue_url}/back")
      request_info(req_hash, SqsSendMessagesParser.new)
    rescue
      on_exception
    end
    
      # Deletes message from queue. Returns +true+ or an exception.
      #
      #  sqs.delete_message('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', '12345678904...0987654321') #=> true
      #
    def delete_message(queue_url, message_id)
      req_hash = generate_request('DeleteMessage', 
                                  'MessageId' => message_id,
                                  :queue_url  => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end
    
      # Changes message visibility timeout. Returns +true+ or an exception.
      #
      #  sqs.change_message_visibility('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', '1234567890...0987654321', 10) #=> true
      #
    def change_message_visibility(queue_url, message_id, visibility_timeout=0)
      req_hash = generate_request('ChangeMessageVisibility', 
                                  'MessageId'         => message_id,
                                  'VisibilityTimeout' => visibility_timeout.to_s,
                                  :queue_url          => queue_url)
      request_info(req_hash, SqsStatusParser.new)
    rescue
      on_exception
    end
    
      # Returns queue url by queue short name or +nil+ if queue is not found
      #
      #  sqs.queue_url_by_name('my_awesome_queue') #=> 'http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue'
      #
    def queue_url_by_name(queue_name)
      return queue_name if queue_name.include?('/')
      queue_urls = list_queues(queue_name)
      queue_urls.each do |queue_url|
        return queue_url if queue_name_by_url(queue_url) == queue_name
      end
      nil
    rescue
      on_exception
    end

      # Returns short queue name by url.
      #
      #  RightSqs.queue_name_by_url('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> 'my_awesome_queue'
      #
    def self.queue_name_by_url(queue_url)
      queue_url[/[^\/]*$/]
    rescue
      on_exception
    end
    
      # Returns short queue name by url.
      #
      #  sqs.queue_name_by_url('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> 'my_awesome_queue'
      #
    def queue_name_by_url(queue_url)
      self.class.queue_name_by_url(queue_url)
    rescue
      on_exception
    end

      # Returns approximate amount of messages in queue.
      #
      #  sqs.get_queue_length('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> 3
      #
    def get_queue_length(queue_url)
      get_queue_attributes(queue_url)['ApproximateNumberOfMessages'].to_i
    rescue
      on_exception
    end

      # Removes all visible messages from queue. Return +true+ or an exception.
      #
      #  sqs.clear_queue('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> true
      #
    def clear_queue(queue_url)
      while (m = pop_message(queue_url)) ; end   # delete all messages in queue
      true
    rescue
      on_exception
    end

      # Deletes queue then re-creates it (restores attributes also). The fastest method to clear big queue or queue with invisible messages. Return +true+ or an exception.
      #
      #  sqs.force_clear_queue('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> true
      #
    def force_clear_queue(queue_url)
      queue_name       = queue_name_by_url(queue_url)
      queue_attributes = get_queue_attributes(queue_url)
      force_delete_queue(queue_url)
      create_queue(queue_name)
        # hmmm... The next like is a trick. Amazon do not want change attributes immediately after queue creation
        # So we do 'empty' get_queue_attributes. Probably they need some time to allow attributes change.
      get_queue_attributes(queue_url)  
      queue_attributes.each{ |attribute, value| set_queue_attributes(queue_url, attribute, value) }
      true
    rescue
      on_exception
    end

      # Deletes queue even if it has messages. Return +true+ or an exception.
      #
      #  force_delete_queue('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=> true
      #
      # P.S. same as <tt>delete_queue('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', true)</tt>
    def force_delete_queue(queue_url)
      delete_queue(queue_url, true)
    rescue
      on_exception
    end

      # Reads first accessible message from queue. Returns message as a hash: <tt>{:id=>'message_id', :body=>'message_body'}</tt> or +nil+.
      #
      #  sqs.receive_message('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 10) #=>
      #    {:id=>"12345678904GEZX9746N|0N9ED344VK5Z3SV1DTM0|1RVYH4X3TJ0987654321", :body=>"message_1"}
      #
    def receive_message(queue_url, visibility_timeout=nil)
      result = receive_messages(queue_url, 1, visibility_timeout)
      result.blank? ? nil : result[0]
    rescue
      on_exception
    end
    
      # Same as send_message
    alias_method :push_message, :send_message
    
      # Pops (retrieves and deletes) up to 'number_of_messages' from queue. Returns an array of retrieved messages in format: <tt>[{:id=>'message_id', :body=>'message_body'}]</tt>.
      #
      #   sqs.pop_messages('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue', 3) #=>
      #    [{:id=>"12345678904GEZX9746N|0N9ED344VK5Z3SV1DTM0|1RVYH4X3TJ0987654321", :body=>"message_1"}, ..., {}]
      #
    def pop_messages(queue_url, number_of_messages=1)
      messages = receive_messages(queue_url, number_of_messages)
      messages.each do |message|
        delete_message(queue_url, message[:id])
      end
      messages
    rescue
      on_exception
    end

      # Pops (retrieves and  deletes) first accessible message from queue. Returns the message in format <tt>{:id=>'message_id', :body=>'message_body'}</tt> or +nil+.
      #
      #  sqs.pop_message('http://queue.amazonaws.com/ZZ7XXXYYYBINS/my_awesome_queue') #=>
      #    {:id=>"12345678904GEZX9746N|0N9ED344VK5Z3SV1DTM0|1RVYH4X3TJ0987654321", :body=>"message_1"}
      #
    def pop_message(queue_url)
      messages = pop_messages(queue_url)
      messages.blank? ? nil : messages[0]
    rescue
      on_exception
    end

    #-----------------------------------------------------------------
    #      PARSERS: Status Response Parser
    #-----------------------------------------------------------------

    class SqsStatusParser < RightAWSParser # :nodoc:
      def tagend(name)
        if name == 'StatusCode'
          @result = @text=='Success' ? true : false
        end
      end
    end

    #-----------------------------------------------------------------
    #      PARSERS: Queue
    #-----------------------------------------------------------------

    class SqsCreateQueueParser < RightAWSParser # :nodoc:
      def tagend(name)
        @result = @text if name == 'QueueUrl'
      end
    end

    class SqsListQueuesParser < RightAWSParser # :nodoc:
      def reset
        @result = []
      end
      def tagend(name)
        @result << @text if name == 'QueueUrl'
      end
    end

    class SqsGetQueueAttributesParser < RightAWSParser # :nodoc:
      def reset
        @result = {}
      end
      def tagend(name)
        case name 
          when 'Attribute' ; @current_attribute          = @text
          when 'Value'     ; @result[@current_attribute] = @text
  #        when 'StatusCode'; @result['status_code']      = @text
  #        when 'RequestId' ; @result['request_id']       = @text
        end
      end
    end

    #-----------------------------------------------------------------
    #      PARSERS: Timeouts
    #-----------------------------------------------------------------

    class SqsGetVisibilityTimeoutParser < RightAWSParser # :nodoc:
      def tagend(name)
        @result = @text.to_i if name == 'VisibilityTimeout'
      end
    end

    #-----------------------------------------------------------------
    #      PARSERS: Permissions
    #-----------------------------------------------------------------

    class SqsListGrantsParser < RightAWSParser # :nodoc:
      def reset
        @result = []
      end
      def tagstart(name, attributes)
        @current_perms = {} if name == 'GrantList'
      end
      def tagend(name)
        case name
          when 'ID'         ; @current_perms[:id]         = @text
          when 'DisplayName'; @current_perms[:name]       = @text
          when 'Permission' ; @current_perms[:permission] = @text
          when 'GrantList'  ; @result << @current_perms 
        end
      end
    end

    #-----------------------------------------------------------------
    #      PARSERS: Messages
    #-----------------------------------------------------------------

    class SqsReceiveMessagesParser < RightAWSParser # :nodoc:
      def reset
        @result = []
      end
      def tagstart(name, attributes)
        @current_message = {} if name == 'Message'
      end
      def tagend(name)
        case name
          when 'MessageId'  ; @current_message[:id]   = @text
          when 'MessageBody'; @current_message[:body] = @text
          when 'Message'    ; @result << @current_message
        end
      end
    end

    class SqsSendMessagesParser < RightAWSParser # :nodoc:
      def tagend(name)
        @result = @text if name == 'MessageId'
      end
    end
    
  end

end