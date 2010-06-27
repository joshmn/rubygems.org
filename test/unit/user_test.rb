require File.dirname(__FILE__) + '/../test_helper'

class UserTest < ActiveSupport::TestCase
  should_have_many :rubygems, :through => :ownerships
  should_have_many :ownerships
  should_have_many :subscribed_gems, :through => :subscriptions
  should_have_many :subscriptions
  should_have_many :web_hooks

  context "validations" do
    context "handle" do
      should "begin with a lowercase letter" do
        user = Factory.build(:user, :handle => "1abcde")
        assert ! user.valid?
        assert_equal "is invalid", user.errors.on(:handle)

        user.handle = "abcdef"
        user.valid?
        assert_nil user.errors.on(:handle)
      end

      should "contain only lowercase letters, numbers, dashes and underscores" do
        user = Factory.build(:user, :handle => "abc^%def")
        assert ! user.valid?
        assert_equal "is invalid", user.errors.on(:handle)

        user.handle = "abc1_two-four"
        user.valid?
        assert_nil user.errors.on(:handle)
      end

      should "be between 3 and 15 characters" do
        user = Factory.build(:user, :handle => "a")
        assert ! user.valid?
        assert_equal "is too short (minimum is 3 characters)", user.errors.on(:handle)

        user.handle = "a" * 16
        assert ! user.valid?
        assert_equal "is too long (maximum is 15 characters)", user.errors.on(:handle)

        user.handle = "abcdef"
        user.valid?
        assert_nil user.errors.on(:handle)
      end

      should "be invalid when blank" do
        user = Factory.build(:user, :handle => "")
        assert ! user.valid?
      end
    end
  end

  context "with a user" do
    setup do
      @user = Factory(:user)
    end

    should "authenticate with email/password" do
      assert_equal @user, User.authenticate(@user.email, @user.password)
    end

    should "authenticate with handle/password" do
      assert_equal @user, User.authenticate(@user.handle, @user.password)
    end

    should "transfer over rubyforge user" do
      @rubyforger = Factory(:rubyforger, :email => @user.email, :encrypted_password => Digest::MD5.hexdigest(@user.password))
      assert_equal @user, User.authenticate(@user.email, @user.password)
      assert ! Rubyforger.exists?(@rubyforger.id)
    end

    should "not transfer over rubyforge user if password is wrong" do
      @rubyforger = Factory(:rubyforger, :email => @user.email, :encrypted_password => Digest::MD5.hexdigest(@user.password))
      assert_nil User.authenticate(@user.email, "trogdor")
      assert Rubyforger.exists?(@rubyforger.id)
    end

    should "not authenticate with bad handle, good password" do
      assert_nil User.authenticate("bad", @user.password)
    end

    should "not authenticate with bad email, good password" do
      assert_nil User.authenticate("bad@example.com", @user.password)
    end

    should "not authenticate with good email, bad password" do
      assert_nil User.authenticate(@user.email, "bad")
    end

    should "only have email when boiling down to json or yaml" do
      json = JSON.parse(@user.to_json)
      yaml = YAML.load(@user.to_yaml)

      hash = {"email" => @user.email}
      assert_equal hash, json
      assert_equal hash, yaml
    end

    should "create api key" do
      assert_not_nil @user.api_key
    end

    should "give email if handle is not set for name" do
      @user.handle = nil
      assert_nil @user.handle
      assert_equal @user.email, @user.name
    end

    should "give handle if handle is set for name" do
      @user.handle = "qrush"
      @user.save
      assert_equal @user.handle, @user.name
    end

    should "have a 32 character hexadecimal api key" do
      assert @user.api_key =~ /^[a-f0-9]{32}$/
    end

    should "reset api key" do
      assert_changed(@user, :api_key) do
        @user.reset_api_key!
      end
    end

    should "only return approved rubygems" do
      my_rubygem = Factory(:rubygem)
      other_rubygem = Factory(:rubygem)
      Factory(:ownership, :user => @user, :rubygem => my_rubygem, :approved => true)
      Factory(:ownership, :user => @user, :rubygem => other_rubygem, :approved => false)

      assert_equal [my_rubygem], @user.rubygems
    end

    context "with a confirmed email address" do
      setup do
        @user = Factory(:email_confirmed_user)
        @user.confirmation_token = nil
        @user.save
      end

      should "generate a new confirmation token when the email gets changed" do
        @user.update_attributes(:email => "changed@example.com")
        assert @user.email_reset
      end
    end

    context "with subscribed gems" do
      setup do
        @subscribed_gem   = Factory(:rubygem)
        @unsubscribed_gem = Factory(:rubygem)
        Factory(:subscription, :user => @user, :rubygem => @subscribed_gem)
      end

      should "only fetch the subscribed gems with #subscribed_gems" do
        assert_contains         @user.subscribed_gems, @subscribed_gem
        assert_does_not_contain @user.subscribed_gems, @unsubscribed_gem
      end
    end

    context "with the rubyforge user set up" do
      setup do
        ENV["RUBYFORGE_IMPORTER"] = "42"
      end

      should "be true if rubyforge user is pushing to us" do
        stub(@user).id { ENV["RUBYFORGE_IMPORTER"] }
        assert @user.rubyforge_importer?
      end

      should "be false if it's not the rubyforge user" do
        assert ! @user.rubyforge_importer?
      end

      teardown do
        ENV["RUBYFORGE_USER"] = nil
      end
    end

    should "have all gems and specific gems for hooks" do
      rubygem = Factory(:rubygem)
      rubygem_hook = Factory(:web_hook,
                             :user    => @user,
                             :rubygem => rubygem)
      global_hook  = Factory(:global_web_hook,
                             :user    => @user)

      all_hooks = @user.all_hooks

      assert_equal rubygem_hook, all_hooks[rubygem.name].first
      assert_equal global_hook, all_hooks["all gems"].first
    end

    should "have all gems for hooks" do
      global_hook  = Factory(:global_web_hook, :user => @user)
      all_hooks = @user.all_hooks

      assert_equal global_hook, all_hooks["all gems"].first
      assert_equal 1, all_hooks.keys.size
    end

    should "have only specific for hooks" do
      rubygem = Factory(:rubygem)
      rubygem_hook = Factory(:web_hook,
                             :user    => @user,
                             :rubygem => rubygem)
      all_hooks = @user.all_hooks

      assert_equal rubygem_hook, all_hooks[rubygem.name].first
      assert_equal 1, all_hooks.keys.size
    end
  end
end
