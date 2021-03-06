#***********************************************************
#* Copyright (c) 2006, Zhimin Zhan.
#* Distributed open-source, see full license in MIT-LICENSE
#***********************************************************

begin
  require 'watir'
  require 'watir/ie'
  require 'watir/contrib/enabled_popup'
  require 'watir/contrib/visible'
  require 'watir/close_all'
  $watir_loaded = true
rescue LoadError => e
  $watir_loaded = false
end

begin
  require "rubygems";
  require "firewatir";
  $firewatir_loaded = true
rescue LoadError => e
  $firewatir_loaded = false
end

raise "You have must at least Watir or Firewatir installed" unless $watir_loaded || $firewatir_loaded

module RWebUnit

  ##
  #  Wrapping WATIR IE and FireWatir Firefox
  #
  class WebBrowser

    attr_accessor :context

    def initialize(base_url = nil, existing_browser = nil, options = {})
      default_options = {:speed => "zippy", :visible => true,
      :highlight_colour => 'yellow',  :close_others => true}
      options = default_options.merge options
      @context = Context.new base_url if base_url

      if (existing_browser) then
        @browser = existing_browser
      else
        if (options[:firefox] &&  $firewatir_loaded) || ($firewatir_loaded and !$watir_loaded)
          # JSSH is running, 9997
          begin
            require 'net/telnet'
            firefox_jssh = Net::Telnet::new("Host" => "127.0.0.1", "Port" => 9997)
            FireWatir::Firefox.firefox_started = true
          rescue => e
            # puts "debug: XXX #{e}"
            sleep 1
          end
          @browser = FireWatir::Firefox.start(base_url)
        elsif $watir_loaded
          @browser = Watir::IE.new
        end
      end

      raise "rWebUnit initialiazation error, most likely Watir or Firewatir not present" if @browser.nil?
      if  $watir_loaded && @browser.class == Watir::IE
        if $ITEST2_EMULATE_TYPING  &&  $ITEST2_TYPING_SPEED then
          @browser.set_slow_speed if $ITEST2_TYPING_SPEED == 'slow'
          @browser.set_fast_speed if $ITEST2_TYPING_SPEED == 'fast'
        else
          @browser.speed = :zippy
        end
        @browser.activeObjectHighLightColor = options[:highlight_colour]
        @browser.visible = options[:visible] unless $HIDE_IE
        @browser.close_others if options[:close_others]
      end

    end

    def self.reuse(base_url, options)
      if RUBY_PLATFORM.downcase.include?("mswin") && $ITEST2_BROWSER != "Firefox"
        Watir::IE.each do |browser_window|
          return WebBrowser.new(base_url, browser_window, options)
        end
        puts "no browser instance found"
        WebBrowser.new(base_url, nil, options)
      else
        WebBrowser.new(base_url, nil, options)
      end
    end

    # for popup windows
    def self.new_from_existing(underlying_browser, web_context = nil)
      return WebBrowser.new(web_context ? web_context.base_url : nil, underlying_browser, {:close_others => false})
    end


    ##
    #  Delegate to Watir
    #
    [:button, :cell, :checkbox, :div, :form, :frame, :h1, :h2, :h3, :h4, :h5, :h6, :hidden, :image, :li, :link, :map, :pre, :row, :radio, :select_list, :span, :table, :text_field, :paragraph, :file_field, :label].each do |method|
      define_method method do |*args|
        @browser.send(method, *args)
      end
    end
    alias td cell
    alias check_box checkbox  # seems watir doc is wrong, checkbox not check_box
    alias tr row

    # FireWatir does not support area directly, treat it as text_field
    def area(*args)
      if is_firefox?
        text_field(*args)
      else
        @browser.send("area", *args)
      end
    end

    def contains_text(text)
      @browser.contains_text(text);
    end

    def page_source
      @browser.html()
      #@browser.document.body
    end
    alias html_body page_source

    def html
      @browser.html
    end

    def text
      @browser.text
    end

    def page_title
      if is_firefox?
        @browser.title
      else
        @browser.document.title
      end
    end

    [:images, :links, :buttons, :select_lists, :checkboxes, :radios, :text_fields].each do |method|
      define_method method do
        @browser.send(method)
      end
    end

    # current url
    def url
      @browser.url
    end

    def base_url=(new_base_url)
      if @context
        @conext.base_url = new_base_url
        return
      end
      @context = Context.new base_url
    end

    def is_firefox?
      begin
        @browser.class == FireWatir::Firefox
      rescue => e
        return false
      end
    end

    # Close the browser window.  Useful for automated test suites to reduce
    # test interaction.
    def close_browser
      if is_firefox? then
        @browser.close
      else
        @browser.getIE.quit
      end
      sleep 2
    end
    alias close close_browser

    #TODO determine browser type, check FireWatir support or not
    def self.close_all_browsers
      if RUBY_PLATFORM.downcase.include?("mswin")
        Watir::IE.close_all
      else
        # raise "not supported in FireFox yet."
      end
    end

    def full_url(relative_url)
      if @context && @context.base_url
        @context.base_url + relative_url
      else
        relative_url
      end
    end

    def begin_at(relative_url)
      @browser.goto full_url(relative_url)
    end

    def browser_opened?
      begin
        @browser != nil
      rescue => e
        return false
      end
    end

    # Some browsers (i.e. IE) need to be waited on before more actions can be
    # performed.  Most action methods in Watir::Simple already call this before
    # and after.
    def wait_for_browser
      @browser.waitForIE unless is_firefox?
    end


    # A convenience method to wait at both ends of an operation for the browser
    # to catch up.
    def wait_before_and_after
      wait_for_browser
      yield
      wait_for_browser
    end


    [:back, :forward, :refresh, :focus, :close_others].each do |method|
      define_method(method) do
        @browser.send(method)
      end
    end
    alias refresh_page refresh
    alias go_back back
    alias go_forward forward

    def goto_page(page)
      @browser.goto full_url(page);
    end

    def goto_url(url)
      @browser.goto url
    end

    # text fields
    def enter_text_into_field_with_name(name, text)
      if is_firefox?
        wait_before_and_after { text_field(:name, name).value = text }
        sleep 0.3
      else
        wait_before_and_after { text_field(:name, name).set(text) }
      end
    end
    alias set_form_element enter_text_into_field_with_name
    alias enter_text enter_text_into_field_with_name

    #links
    def click_link_with_id(link_id)
      wait_before_and_after { link(:id, link_id).click }
    end

    def click_link_with_text(text)
      wait_before_and_after { link(:text, text).click }
    end

    ##
    # buttons

    def click_button_with_id(id)
      wait_before_and_after { button(:id, id).click }
    end

    def click_button_with_name(name)
      wait_before_and_after { button(:name, name).click }
    end

    def click_button_with_caption(caption)
      wait_before_and_after { button(:caption, caption).click }
    end

    def click_button_with_value(value)
      wait_before_and_after { button(:value, value).click }
    end

    def select_option(selectName, option)
      select_list(:name, selectName).select(option)
    end

    # submit first submit button
    def submit(buttonName = nil)
      if (buttonName.nil?) then
        buttons.each { |button|
          next if button.type != 'submit'
          button.click
          return
        }
      else
        click_button_with_name(buttonName)
      end
    end

    # checkbox
    def check_checkbox(checkBoxName, values=nil)
      if values
        values.class == Array ? arys = values : arys = [values]
        arys.each {|cbx_value|
          checkbox(:name, checkBoxName, cbx_value).set
        }
      else
        checkbox(:name, checkBoxName).set
      end
    end

    def uncheck_checkbox(checkBoxName, values = nil)
      if values
        values.class == Array ? arys = values : arys = [values]
        arys.each {|cbx_value|
          checkbox(:name, checkBoxName, cbx_value).clear
        }
      else
        checkbox(:name, checkBoxName).clear
      end
    end


    # the method is protected in JWebUnit
    def click_radio_option(radio_group, radio_option)
      radio(:name, radio_group, radio_option).set
    end

    def clear_radio_option(radio_group, radio_option)
      radio(:name, radio_group, radio_option).clear
    end

    def element_by_id(elem_id)
      if is_firefox?
        # elem = @browser.document.getElementById(elem_id)
        elem = div(:id, elem_id) || label(:id, elem_id)  || button(:id, elem_id) || span(:id, elem_id) || hidden(:id, elem_id) || link(:id, elem_id) || radio(:id, elem_id)
      else
        elem = @browser.document.getElementById(elem_id)
      end
    end

    def element_value(elementId)
      if is_firefox? then
        elem = element_by_id(elementId)
        elem ? elem.invoke('innerText') : nil
      else
        elem = element_by_id(elementId)
        elem ? elem.invoke('innerText') : nil
      end
    end

    def element_source(elementId)
      elem = element_by_id(elementId)
      assert_not_nil(elem, "HTML element: #{elementId} not exists")
      elem.innerHTML
    end

    def select_file_for_upload(file_field, file_path)
      normalized_file_path = RUBY_PLATFORM.downcase.include?("mswin") ? file_path.gsub("/", "\\") : file_path
      file_field(:name, file_field).set(normalized_file_path)
    end

    def start_window(url = nil)
      @browser.start_window(url);
    end

    # Attach to existing browser
    #
    # Usage:
    #    WebBrowser.attach_browser(:title, "iTest2")
    #    WebBrowser.attach_browser(:url, "http://www.itest2.com")
    #    WebBrowser.attach_browser(:url, "http://www.itest2.com", {:browser => "Firefox", :base_url => "http://www.itest2.com"})
    #    WebBrowser.attach_browser(:title, /agileway\.com\.au\/attachment/)  # regular expression
    def self.attach_browser(how, what, options={})
      default_options = {:browser => "IE"}
      options = default_options.merge(options)
      site_context = Context.new(options[:base_url]) if options[:base_url]
      if (options[:browser] == "Firefox")
        return WebBrowser.new_from_existing(FireWatir::Firefox.new.attach(how, what), site_context)
      else
        return WebBrowser.new_from_existing(Watir::IE.attach(how, what), site_context)
      end
    end

    # Attach a Watir::IE instance to a popup window.
    #
    # Typical usage
    #   new_popup_window(:url => "http://www.google.com/a.pdf")
    def new_popup_window(options, browser = "ie")
      if is_firefox?
        raise "not implemented"
      else
        if options[:url]
          Watir::IE.attach(:url, options[:url])
        elsif options[:title]
          Watir::IE.attach(:title, options[:title])
        else
          raise 'Please specify title or url of new pop up window'
        end
      end
    end

    # ---
    # For deubgging
    # ---
    def dump_response(stream = nil)
      stream.nil? ?  puts(page_source) : stream.puts(page_source)
    end

    # A Better Popup Handler using the latest Watir version. Posted by Mark_cain@rl.gov
    #
    # http://wiki.openqa.org/display/WTR/FAQ#FAQ-HowdoIattachtoapopupwindow%3F
    #
    def start_clicker( button, waitTime= 9, user_input=nil)
      # get a handle if one exists
      hwnd = @browser.enabled_popup(waitTime)
      if (hwnd)  # yes there is a popup
        w = WinClicker.new
        if ( user_input )
          w.setTextValueForFileNameField( hwnd, "#{user_input}" )
        end
        # I put this in to see the text being input it is not necessary to work
        sleep 3
        # "OK" or whatever the name on the button is
        w.clickWindowsButton_hwnd( hwnd, "#{button}" )
        #
        # this is just cleanup
        w = nil
      end
    end

    # return underlying browser
    def ie
      raise "can't call this as it is configured to use Firefox" if is_firefox?
      @browser
    end

    def firefox
      raise "can't call this as it is configured to use IE" unless is_firefox?
      @browser
    end

    def save_page(file_name = nil)
      file_name ||= Time.now.strftime("%Y%m%d%H%M%S") + ".html"
      puts "about to save page: #{File.expand_path(file_name)}"
      File.open(file_name, "w").puts page_source
    end


    def self.is_windows?
      RUBY_PLATFORM.downcase.include?("mswin")
    end

  end
end
