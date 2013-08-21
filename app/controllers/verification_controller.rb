class VerificationController < ApplicationController
  before_action :signed_in_user
	before_action :is_unverified
  before_action :account_age

  def start
  end

  def complete
    profile_url = params.require(:profile_url)
    regex_pattern = /\Ahttp:\/\/forums\.somethingawful\.com\/member\.php\?action=getinfo&userid=\d+\z/

    if !profile_url.match(regex_pattern)
      flash[:error] = "Profile URL is't correct. Must look like http://forums.somethingawful.com/member.php?action=getinfo&userid=####"
      redirect_to action: 'start'
    else
      results = verify_profile(profile_url)

      unless results.values.include?(false)
        current_user.profile_id = profile_url.match(/\d+\z/).to_s.to_i
        current_user.is_verified = true
        current_user.save
        flash[:success] = "You're now verified. Enjoy!"
        redirect_to(root_url)
      else
        # Display errors and redo
        unless results[:reg_date]
          flash[:error] += "Account isn't older than #{@account_age.strftime("%b %-d, %Y")}.<br>"
        end

        unless results[:string]
          flash[:error] += "Didn't find #{@expected_token} in Occupation field.<br>"
        end

        redirect_to action: 'start'
      end
    end
  end

  private

  # Work around for a Rubyism
  def expected_token
    @expected_token ||= current_user.verification_token.to_s
  end

  def account_age
    # Use .days rather than .months since days in month vary
    @account_age = 90.days.ago.at_midnight
  end

  def is_unverified
  	redirect_to(root_url) if current_user.is_verified?
  end

  def verify_profile(url)
    require 'mechanize'
    results = Hash.new
    agent = Mechanize.new
    agent.user_agent = 'SA Profile Verifier by BFGoons.com'
    cookie_file = 'sa_cookie.yaml'

    # Load cookie file if exists
    if File.exist?(cookie_file)
      agent.cookie_jar.load(cookie_file)
    end

    # Determine if login needed
    page = agent.get(url)
    requires_login = false
    login_link = /\/account\.php\?action=loginform/
    page.links.each do |link|
      if link.href =~ login_link
        requires_login = true
      end
    end

    # Login if needed
    if requires_login
      login_form = page.link_with(href: login_link).click.forms[1]
      login_form.username = ENV['SA_USERNAME']
      login_form.password = ENV['SA_PASSWORD']
      page = agent.submit(login_form)
    end

    # Save cookie file
    agent.cookie_jar.save(cookie_file, session: true)

    # Get registration date
    reg_date = Time.parse(page.search('dd.registered').inner_text)
    results[:reg_date] = (reg_date < @account_age)

    # Find string
    string = 'Occupation' + expected_token
    additional_info_text = page.search('dl.additional').inner_text
    results[:string] = (additional_info_text.match(string).to_s == string)

    results
  end

end
