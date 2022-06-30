require 'json'
require 'net/http'
require 'open-uri'
require 'bitcoin'

class Wallet
  include Bitcoin::Builder

  attr_accessor :key

  module BlockstreamApi
    extend self
    BLOCKSTREAM_API_URL = "https://blockstream.info/testnet/api/".freeze

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

    def addr_utxo_list(addr)
      utxo_ids_by_addr(addr).map { |txid| tx_by_id txid }
    end

    def broadcast_transaction(tx)
      url = URI("#{BLOCKSTREAM_API_URL}tx")
      Net::HTTP.post url, tx.to_payload.bth
    end
  end

  class << self
    def convert_str_btc_to_satoshi(str)
      (str.to_f * 100_000_000).to_i
    end
  end

  def initialize(key)
    @key = key
    @transaction = []
  end

  def addr
    @key.addr
  end

  def build_transaction(send_to_addr:, shatoshi:)
    utxos = BlockstreamApi.addr_utxo_list(addr)

    # error 1 byte per each input
    fee = utxos.count * 148 + 2 * 34 + 10
    balance_after_tx = BlockstreamApi.addr_balace(addr) - shatoshi - fee
    raise "Not enough balance" if balance_after_tx < 0
  
    build_tx do |transaction|
      utxos.each do |utxo|
        make_tx_input tx: transaction, prev_tx: utxo,
                      prev_tx_index: addr_index_in_tx_out(tx: utxo, addr: addr), key: key
      end
  
      transaction.output do |o|
        o.value shatoshi
        o.script { |s| s.recipient send_to_addr }
      end
  
      transaction.output do |o|
        o.value balance_after_tx
        o.script {|s| s.recipient addr }
      end
    end
  end

  private

  def make_tx_input(tx:, prev_tx:, prev_tx_index:, sing_key:)
    tx.input do |i|
      i.prev_out prev_tx
      i.prev_out_index prev_tx_index
      i.signature_key sing_key
    end
  end

  def addr_index_in_tx_out(tx:, addr:)
    tx.to_hash(with_address: true)['out'].find_index { |o| o['address'] == addr }
  end
end
