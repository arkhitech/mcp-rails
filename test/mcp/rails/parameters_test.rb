require "test_helper"

module MCP
  module Rails
    class ParametersTest < ActionController::TestCase
      def setup
        @temp_dir = Dir.mktmpdir
        @key_path = File.join(@temp_dir, "bypass_key.txt")
        MCP::Rails.configure do |config|
          config.bypass_key_path = @key_path
          config.base_url = "http://example.com:3000"
        end
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end

      def setup_controller(controller)
        controller = controller.new
        @request = ActionController::TestRequest.create(controller)
        controller.request = @request
        controller.response = ActionDispatch::TestResponse.new
        controller
      end

      test "permitted_params handles nested parameters" do
        controller = setup_controller(NestedParametersController)
        controller.action_name = "create"
        params = controller.class.permitted_params(:create)

        user_param = params.find { |p| p[:name] == :user }
        assert user_param[:required]

        nested_params = user_param[:nested]
        name_param = nested_params.find { |p| p[:name] == :name }
        address_param = nested_params.find { |p| p[:name] == :address }

        assert_equal :string, name_param[:type]
        assert name_param[:required]
        assert address_param[:nested].present?
      end

      test "permitted_params handles array parameters" do
        controller = setup_controller(ArrayParametersController)
        controller.action_name = "create"
        params = controller.class.permitted_params(:create)

        tags_param = params.find { |p| p[:name] == :tags }
        items_param = params.find { |p| p[:name] == :items }

        assert_equal :array, tags_param[:type]
        assert_equal [ "tag1", "tag2" ], tags_param[:example]

        ids_param = items_param[:nested].find { |p| p[:name] == :ids }
        assert_equal :array, ids_param[:type]
        assert ids_param[:required]
      end

      test "resource_params filters parameters according to definition" do
        controller = setup_controller(BasicParametersController)
        controller.action_name = "create"
        controller.params = ActionController::Parameters.new({
          name: "Test Name",
          age: 25,
          invalid_param: "should be filtered"
        })

        filtered_params = @controller.send(:resource_params)
        assert_equal "Test Name", filtered_params[:name]
        assert_equal 25, filtered_params[:age]
        assert_not_includes filtered_params.keys, :invalid_param
      end

      test "resource_params raises error for missing required parameters" do
        @controller.action_name = "nested"
        @controller.params = ActionController::Parameters.new({
          user: {}
        })

        error = assert_raises(ActionController::ParameterMissing) do
          @controller.send(:resource_params)
        end
        assert_match(/param is missing or the value is empty or invalid: user/, error.message)
      end

      test "resource_params handles shared parameters" do
        controller = setup_controller(SharedParametersController)
        controller.action_name = "create"
        controller.params = ActionController::Parameters.new({
          name: "Test Name",
          email: "test@example.com",
          phone: "123-456-7890"
        })

        filtered_params = @controller.send(:resource_params)
        assert_equal "Test Name", filtered_params[:name]
        assert_equal "test@example.com", filtered_params[:email]
        assert_equal "123-456-7890", filtered_params[:phone]
      end
    end
  end
end
