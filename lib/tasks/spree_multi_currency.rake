# encoding: utf-8

require 'open-uri'
require 'nokogiri'
# add custom rake tasks here
namespace :spree_multi_currency do
  eur_hash = { num_code: '978', char_code: 'EUR', name: 'Euro' }

  namespace :currency do
    desc "Load start currencies"

    task :load => :environment do
      keys = [:usd, :rub, :eur]
      keys.each do |key|
        x = ::Money::Currency.table[key]
        unless Spree::Currency.exists?(name: key)
          Spree::Currency.create(char_code: x[:iso_code],name: key,num_code: x[:iso_numeric],basic:(key==:usd) ? true :false)
        end
      end
    end
  end

  namespace :rates do
    desc 'Курс Сбербанка РФ http://www.cbr.ru'
    task :cbr => :environment do
      basic = Spree::Currency.find_by_basic(1)
      unless basic.present?
        basic  = Spree::Currency.get('643', { num_code: '643', char_code: 'RUB', name: 'Российский рубль' })
        basic.basic!
      end
      url = "http://www.cbr.ru/scripts/XML_daily.asp?date_req=#{Time.now.strftime('%d/%m/%Y')}"
      basic_value = 1
      currencies = []
      data = Nokogiri::XML.parse(open(url))
      date_str = data.xpath('//ValCurs').attr('Date').to_s
      date =  date_str.split(date_str.include?('/') ? '/' : '.').reverse.join('-')
      data.xpath('//ValCurs/Valute').each do |valute|
        char_code  = valute.xpath('./CharCode').text.to_s
        num_code   = valute.xpath('./NumCode').text.to_s
        name       = valute.xpath('./Name').text.to_s
        value      = valute.xpath('./Value').text.gsub(',', '.').to_f
        nominal    = valute.xpath('./Nominal').text
        if basic.char_code == char_code
          basic_value = value
        end
        
        currencies << { num_code: num_code, char_code: char_code,name: name, value: value,nominal: nominal}
      
      
      end
      currencies << { num_code: '643', char_code: 'RUB', name: 'Российский рубль', value: 1, nominal: 1 }   # basic may not be RUB
      currencies.each do |c|
        if c[:char_code] ==  basic.char_code    # need not insert basic
          next
        end
        
        currency   = Spree::Currency.get(c[:num_code], { :num_code => c[:num_code], :char_code => c[:char_code], :name => c[:name] })
        currency && Spree::CurrencyConverter.add(currency, date, c[:value]/basic_value, c[:nominal])
      end
      
    end

    desc 'rates from Yahoo USD->EUR,RUB'
    task :yahoo =>:environment do
      url = 'http://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20yahoo.finance.xchange%20where%20pair%20in%20%28%22USDEUR%22,%20%22USDRUB%22%29&env=store://datatables.org/alltableswithkeys'
      data = Nokogiri::XML.parse(open(url))
      date_str = data.xpath('query').attr('created').to_s.split('T')[0]
      date =  date_str.split('-').reverse.join('-')
      data.xpath('query').xpath('results').children.each do |elem|
        name = elem.xpath('Name').text.to_s.split('/')[-1]
        rate = elem.xpath('Rate').text.to_f
        currency = Spree::Currency.where(char_code: name)[0]
        Spree::CurrencyConverter.add(currency,date,1/rate,1)
      end
    end

    desc 'Rates from European Central Bank'
    task :ecb, [:load_currencies] => :environment do |t, args|
      if args.load_currencies
        Rake::Task['spree_multi_currency:currency:iso4217'].invoke
      end
      
      basic = Spree::Currency.find_by_basic(1)
      unless basic.present?
      
        euro  = Spree::Currency.get('978', eur_hash)
        euro.basic!
      end
      basic_value = 1
      currencies = []
      
      url = 'http://www.ecb.int/stats/eurofxref/eurofxref-daily.xml'
      data = Nokogiri::XML.parse(open(url))
      date = Date.strptime(data.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube').attr('time').to_s, "%Y-%m-%d")
      data.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube//xmlns:Cube').each do |exchange_rate|
        char_code      = exchange_rate.attribute('currency').value.to_s.strip
        nominal, value = exchange_rate.attribute('rate').value.to_f, 1
        
        
        if basic.char_code == char_code

          basic_value = nominal
        end
        
        currencies << {char_code: char_code, value: value,nominal: nominal}
         
      end
      currencies << eur_hash.merge({value: 1, nominal: 1} ) # basic may not be EUR

      currencies.each do |c|
        if c[:char_code] ==  basic.char_code    # need not insert basic
          next
        end
        
        currency = Spree::Currency.find_by_char_code(c[:char_code])
        currency && Spree::CurrencyConverter.add(currency, date, c[:value], c[:nominal]/basic_value)
      end
        
    end

  end

end

