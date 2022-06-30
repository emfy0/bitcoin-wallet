require_relative 'lib/wallet'

Bitcoin.network = :testnet3

if ARGV[0].nil?
  key = Bitcoin::Key.generate
else
  key = Bitcoin::Key.from_base58(ARGV[0])
end

File.open("#{__dir__}/priv.key",'w+') { |f| f.write(key.priv) }

wallet = Wallet.new(key)

$stdout.puts "1. Show balance \n2. Show wallet addr\n3. Make transaction\n4. Show WIF(Base58)"
$stdout.puts "'q' for quit"

input = ''
until input == 'q' do
  input = $stdin.gets.chomp
  case input
  when '1'
    balance = Wallet::BlockstreamApi.addr_balace(wallet.addr)
    $stdout.puts "Balance = #{balance} shatoshi, #{balance.to_f / 100_000_000} ₿"
  when '2'
    $stdout.puts "Wallet addr = #{wallet.addr}"
  when '3'
    $stdout.puts 'Enter Wallet addr'
    until Bitcoin.valid_address?(addr = $stdin.gets.chomp) do
      $stdout.puts 'Invalid address, try again'
    end

    $stdout.puts 'Enter trx sum in ₿'
    until /\A([0-9]*[.])?[0-9]+\z/ === (sum = $stdin.gets.chomp) do
      $stdout.puts 'Invalid sum'
    end
    sum = Wallet.convert_str_btc_to_satoshi(sum)

    begin
      tx = wallet.build_transaction(send_to_addr: addr, shatoshi: sum)

      res = Wallet::BlockstreamApi.broadcast_transaction(tx)
      if res.is_a?(Net::HTTPSuccess)
        $stdout.puts "Successfully broadcast transaction #{res.body}"
      else
        $stdout.puts "Something went wrong #{res.body}"
      end
    rescue RuntimeError => e
      $stdout.puts e.message
    end
  when '4'
    $stdout.puts "Wallet WIF = #{wallet.key.to_base58}"
  when 'q'
    break
  else
    $stdout.puts 'Invalid option'
  end
  $stdout.puts 'Waiting for another user input...'
end

$stdout.puts 'Gracefully stopped'
