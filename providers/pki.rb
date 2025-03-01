action :sign_csr do
    ruby_block 'sign-csr' do
      block do
        require 'net/https'
        require 'http-cookie'
        require 'json'

        hopsworks_port = 8182
        if !new_resource.http_port.nil?
          hopsworks_port = new_resource.http_port.to_i
        else
          if node.attribute?("hopsworks")
            if node['hopsworks'].attribute?("internal")
              if node['hopsworks']['internal'].attribute?("port")
                hopsworks_port = node['hopsworks']['internal']['port'].to_i
              end
            end
          end
        end

        if new_resource.ca_path.nil?
          ca_path = "hopsworks-ca/v2/certificate/host"
        else
          ca_path = new_resource.ca_path
        end
  
        url = URI.parse("https://#{private_recipe_ip("hopsworks","default")}:#{hopsworks_port}/hopsworks-api/api/auth/service")
        ca_url = URI.join("https://#{private_recipe_ip("hopsworks","default")}:#{hopsworks_port}", ca_path)
  
        if new_resource.csr_file.nil?
          raise "csr_file attribute is mandatory"
        end
  
        if new_resource.output_dir.nil?
          output_dir = ::Dir.tmpdir
        else
          output_dir = new_resource.output_dir
        end
  
        params =  {
          :email => node["kagent"]["dashboard"]["user"],
          :password => node["kagent"]["dashboard"]["password"]
        }
  
        response = http_request_follow_redirect(url, form_params: params)
  
        if( response.is_a?( Net::HTTPSuccess ) )
            # your request was successful
            puts "The Response -> #{response.body}"
  
            csr = ::File.read(new_resource.csr_file)
            req_dict = {'csr' => csr}
            if node.attribute?("consul") &&
                node['consul'].attribute?('use_datacenter') &&
                node['consul']['use_datacenter'].casecmp?("true")
              req_dict['region'] = node['consul']['datacenter']
            end

            response = http_request_follow_redirect(ca_url, 
                                                    body: req_dict.to_json,
                                                    authorization: response['Authorization'])
  
            if ( response.is_a? (Net::HTTPSuccess))
              json_response = ::JSON.parse(response.body)
  
              signedCertifificate = json_response['signedCert']
              intermediateCACert = json_response['intermediateCaCert']
              rootCACert = json_response['rootCaCert']
              certificateBundle = signedCertifificate + "\n" + intermediateCACert
              ::File.write("#{output_dir}/signed_certificate.pem", signedCertifificate)
              ::File.write("#{output_dir}/intermediate_ca.pem", intermediateCACert)
              ::File.write("#{output_dir}/certificate_bundle.pem", certificateBundle)
              ::File.write("#{output_dir}/root_ca.pem", rootCACert)
            else
              puts "The Response -> #{response.body}"
              raise "Error signing certificate. #{response.body}"
            end
        else
            puts response.body
            raise "Error logging in"
        end
      end
    end
  end
