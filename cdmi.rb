require "rack"
require "json"

class CDMI
	def call(env)
		req = Rack::Request.new(env)

		if(env["REQUEST_METHOD"] == "GET")
			return(CDMI.get(env))
		end

		if(env["REQUEST_METHOD"] == "OPTIONS")
			# Handle CORS
			response = Rack::Response.new

			response.add_header("Access-Control-Allow-Origin", "*")
			response.add_header("Access-Control-Allow-Methods", env["HTTP_ACCESS-CONTROL-REQUEST-METHOD"])
			response.add_header("Access-Control-Allow-Headers", "x-cdmi-specification-version")
			response.status = 200
			return(response.finish)
		end

		# Unsupported HTTP method
		response = Rack::Response.new
		response.status = 501
		response.finish
	end

	def self.get(env)
		response = Rack::Response.new

		# Basic path sanitization.
		request_path = env["REQUEST_PATH"]
		request_path = request_path.gsub("%20", " ")
		request_path = request_path.gsub("%", "")
		request_path = request_path.gsub("$", "")
		request_path = request_path.gsub("~", "")
		request_path = request_path.gsub("..", "")

		if(env["HTTP_ACCEPT"] && env["REQUEST_PATH"].rindex("/") == env["REQUEST_PATH"].length - 1)
			# Request is for a container or directory

			if(env["HTTP_ACCEPT"].index("application/cdmi-container") != nil)
				return(CDMI.get_container(env))
			else
				# Directory listing not specified in CDMI, not supported.
				response.status = 501
				response.finish
			end
		else
			if(env["HTTP_ACCEPT"] && env["HTTP_ACCEPT"].index("application/cdmi-object") != nil)
				return(CDMI.get_object(env))
			else
				# Basic File access
				begin
					file = File.open(request_path, "r");
					response.write file.read
					file.close

					response.status = 200
				rescue
					response.status = 404
				end

				return(response.finish)
			end
		end

		# Check if the request is for a container or a data object

		response.status = 501
		response.finish
	end

	def self.get_object(env)
		response = Rack::Response.new
		response.add_header("Access-Control-Allow-Origin", "*")

		cdmi_response = Hash.new()

		# Basic path sanitization.
		request_path = env["REQUEST_PATH"]
		request_path = request_path.gsub("%20", " ")
		request_path = request_path.gsub("%", "")
		request_path = request_path.gsub("$", "")
		request_path = request_path.gsub("~", "")
		request_path = request_path.gsub("..", "")

		request_object = request_path.slice(request_path.rindex("/") + 1..request_path.length)

		cdmi_response["objectType"] = "application/cdmi-object"
		response.add_header("Content-Type", "application/cdmi-object")
		cdmi_response["objectName"] = request_object
		cdmi_response["parentURI"] = request_path.slice(0, request_path.rindex(request_object))

		# Populate CDMI Metadata
		cdmi_response["metadata"] = Hash.new()


		begin
			file = File.open(request_path, "r");

			file.close

			mimetype = `file -I \"#{request_path}\"`
			cdmi_response["mimetype"] = mimetype.slice(mimetype.index(": ") + 2..mimetype.index("; ") - 1)

			cdmi_response["metadata"]["cdmi_size"] = File.size(request_path)
			cdmi_response["metadata"]["cdmi_ctime"] = File.ctime(request_path).utc.iso8601
			cdmi_response["metadata"]["cdmi_mtime"] = File.mtime(request_path).utc.iso8601
			cdmi_response["metadata"]["cdmi_atime"] = File.atime(request_path).utc.iso8601

			response.write JSON.pretty_generate(cdmi_response)
			response.status = 200
		rescue Errno::ENOENT => e
			response.status = 404
		rescue Errno::EACCES => e
			response.status = 403
		end

		return(response.finish)
	end

	def self.get_container(env)
		response = Rack::Response.new
		response.add_header("Access-Control-Allow-Origin", "*")

		cdmi_response = Hash.new()

		request_path = env["REQUEST_PATH"]
		request_path = request_path.gsub("%20", " ")
		request_path = request_path.gsub("%", "")
		request_path = request_path.gsub("$", "")
		request_path = request_path.gsub("~", "")
		request_path = request_path.gsub("..", "")

		if(request_path.length > 1)
			request_object = request_path.slice(0, request_path.length - 1)
			request_object = request_object.slice(request_object.rindex("/") + 1, request_object.length) + "/"
			
			mount_path = request_path.slice(0, request_path.length - 1)
		else
			request_object = request_path
			mount_path = request_path
		end

		cdmi_response["objectType"] = "application/cdmi-container"
		response.add_header("Content-Type", "application/cdmi-container")
		cdmi_response["objectName"] = request_object
		cdmi_response["parentURI"] = request_path.slice(0, request_path.rindex(request_object))
		cdmi_response["completionStatus"] = "Complete"

		mounted_volume_source = Hash.new()
		mounted_volume_type = Hash.new()

		mounted_volume_data = `mount`
		mounted_volume_data.each_line do |line|
			mounted_volume_source[line.slice(line.index(" on ") + 4..line.index(" (") - 1)] = line.slice(0..line.index(" on ") - 1) 
			mounted_volume_type[line.slice(line.index(" on ") + 4..line.index(" (") - 1)] = line.slice(line.index(" (") + 2..line.index(", ") - 1)
		end

		# Populate CDMI Metadata
		cdmi_response["metadata"] = Hash.new()

		if(mounted_volume_source[mount_path])
			cdmi_response["metadata"]["import"] = Hash.new()
			cdmi_response["metadata"]["import"]["source"] = mounted_volume_source[mount_path]
			cdmi_response["metadata"]["import"]["type"] = mounted_volume_type[mount_path]
		end

		cdmi_response["metadata"]["cdmi_ctime"] = File.ctime(request_path).utc.iso8601
		cdmi_response["metadata"]["cdmi_mtime"] = File.mtime(request_path).utc.iso8601
		cdmi_response["metadata"]["cdmi_atime"] = File.atime(request_path).utc.iso8601

		# Populate CDMI Children
		begin
			children = Dir.children(request_path).sort

			if(children.count == 0)
				cdmi_response["childrange"] = ""
			else
				cdmi_response["childrange"] = "0-" + (children.count - 1).to_s
			end

			cdmi_response["children"] = Array.new

			children.each do |child|
				if(File.symlink? request_path + child)
					if(File.directory? request_path + child)
						cdmi_response["children"] << child + "/?"
					else
						cdmi_response["children"] << child + "?"
					end
				else
					if(File.directory? request_path + child)
						cdmi_response["children"] << child + "/"
					else
						cdmi_response["children"] << child
					end
				end
			end

			response.write JSON.pretty_generate(cdmi_response)
			response.status = 200
		rescue
			response.status = 404
		end

		return(response.finish)
	end
end
