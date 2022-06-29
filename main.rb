require 'json'
require 'net/http'
require 'open-uri'
require 'bitcoin'

def addr_balace(addr)
  res = open("#{BLOCKSTREAM_API_URL}address/#{addr}")
  addr_info = JSON.parse(res.string)
  chain_stats = addr_info['chain_stats']
  mempool_stats = addr_info['mempool_stats']

  chain_stats['funded_txo_sum'] - chain_stats['spent_txo_sum'] +
    mempool_stats['funded_txo_sum'] - mempool_stats['spent_txo_sum']
end

def utxo_ids_by_addr(addr)
  res = open("#{BLOCKSTREAM_API_URL}address/#{addr}/utxo")
  utxo = JSON.parse(res.string)
  utxo.map { |t| t['txid'] }
end

def tx_by_id(txid)
  res = open("#{BLOCKSTREAM_API_URL}tx/#{txid}/raw")
  Bitcoin::Protocol::Tx.new(res)
end

def addr_utxos(addr)
  utxo_ids_by_addr(addr).map { |txid| tx_by_id txid }
end

def make_tx_input(tx:, prev_tx:, prev_tx_index:, key:)
  tx.input do |i|
    i.prev_out prev_tx
    i.prev_out_index prev_tx_index
    i.signature_key key
  end
end

def addr_index_in_tx_out(tx:, addr:)
  tx.to_hash(with_address: true)['out'].find_index { |o| o['address'] == addr }
end

def build_transaction(addr:, shatoshi:, key:)
  include Bitcoin::Builder

  utxos = addr_utxos(key.addr)

  # error 1 byte per each input
  fee = utxos.count * 148 + 2 * 34 + 10
  balance_after_tx = addr_balace(key.addr) - shatoshi - fee
  raise "Not enough balance" if balance_after_tx < 0

  build_tx do |transaction|
    utxos.each do |utxo|
      make_tx_input tx: transaction, prev_tx: utxo,
                    prev_tx_index: addr_index_in_tx_out(tx: utxo, addr: key.addr), key: key
    end

    transaction.output do |o|
      o.value shatoshi
      o.script { |s| s.recipient addr }
    end

    transaction.output do |o|
      o.value balance_after_tx
      o.script {|s| s.recipient key.addr }
    end
  end
end

def broadcast_transaction(tx:, url:)
  Net::HTTP.post url, tx.to_payload.bth
end

def convert_str_btc_to_satoshi(str)
  (str.to_f * 100_000_000).to_i
end

BLOCKSTREAM_API_URL = "https://blockstream.info/testnet/api/".freeze
Bitcoin.network = :testnet3

FEE = 1000

if ARGV[0].nil?
  key = Bitcoin::Key.generate
else
  key = Bitcoin::Key.from_base58(ARGV[0])
end

File.open("#{__dir__}/priv.key",'w+') { |f| f.write(key.priv) }

$stdout.puts "1. Show balance \n2. Show wallet addr\n3. Make transaction\n4. Show WIF(Base58)"
$stdout.puts "'q' for quit"

input = ''
until input == 'q' do
  input = $stdin.gets.chomp
  case input
  when '1'
    balance = addr_balace(key.addr)
    $stdout.puts "Balance = #{balance} shatoshi, #{balance.to_f / 100_000_000} ₿"
  when '2'
    $stdout.puts "Wallet addr = #{key.addr}"
  when '3'
    begin
      $stdout.puts 'Enter Wallet addr'
      until Bitcoin.valid_address?(addr = $stdin.gets.chomp) do
        $stdout.puts 'Invalid address, try again'
      end

      $stdout.puts 'Enter trx sum in ₿'
      until /\A([0-9]*[.])?[0-9]+\z/ === (sum = $stdin.gets.chomp) do
        $stdout.puts 'Invalid sum'
      end
      sum = convert_str_btc_to_satoshi(sum)

      tx = build_transaction(addr: addr, shatoshi: sum, key: key)

      url = URI("#{BLOCKSTREAM_API_URL}tx")
      res = broadcast_transaction(tx: tx, url: url)
      if res.is_a?(Net::HTTPSuccess)
        $stdout.puts "Successfully broadcast transaction #{res.body}"
      else
        $stdout.puts "Something went wrong #{res.body}"
      end
    rescue RuntimeError => e
      $stdout.puts e.message
    end
  when '4'
    $stdout.puts "Wallet WIF = #{key.to_base58}"
  when 'q'
    break
  else
    $stdout.puts 'Invalid option'
  end
  $stdout.puts 'Waiting for another user input...'
end

$stdout.puts 'Gracefully stopped'
