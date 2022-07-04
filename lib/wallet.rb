require 'json'
require 'net/http'
require 'open-uri'
require 'bitcoin'

class Wallet
  include Bitcoin::Builder

  attr_accessor :key

  module BlockstreamApi
    extend self
    BLOCKSTREAM_API_URL = 'https://blockstream.info/testnet/api/'.freeze

    def addr_balace(address)
      res = open("#{BLOCKSTREAM_API_URL}address/#{address}")
      addr_info = JSON.parse(res.string)
      chain_stats = addr_info['chain_stats']
      mempool_stats = addr_info['mempool_stats']

      chain_stats['funded_txo_sum'] - chain_stats['spent_txo_sum'] +
        mempool_stats['funded_txo_sum'] - mempool_stats['spent_txo_sum']
    end

    def utxo_ids_by_addr(address)
      res = open("#{BLOCKSTREAM_API_URL}address/#{address}/utxo")
      utxo = JSON.parse(res.string)
      utxo.map { |t| t['txid'] }
    end

    def tx_by_id(txid)
      res = open("#{BLOCKSTREAM_API_URL}tx/#{txid}/raw")
      Bitcoin::Protocol::Tx.new(res)
    end

    def addr_utxo_list(address)
      utxo_ids_by_addr(address).map { |txid| tx_by_id txid }
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
  end

  def addr
    @key.addr
  end

  def build_transaction(send_to_addr:, shatoshi:)
    utxos = BlockstreamApi.addr_utxo_list(addr)

    # error 1 byte per each input
    fee = utxos.count * 148 + 2 * 34 + 10
    balance_after_tx = BlockstreamApi.addr_balace(addr) - shatoshi - fee
    raise 'Not enough balance' if balance_after_tx < 0

    utxos.uniq!(&:hash)

    build_tx do |transaction|
      utxos.each do |utxo|
        make_tx_input tx: transaction, prev_tx: utxo,
                      prev_tx_indexs: addr_indexs_in_tx_out(tx: utxo, address: addr), sign_key: key
      end

      transaction.output do |o|
        o.value shatoshi
        o.script { |s| s.recipient send_to_addr }
      end

      transaction.output do |o|
        o.value balance_after_tx
        o.script { |s| s.recipient addr }
      end
    end
  end

  private

  def make_tx_input(tx:, prev_tx:, prev_tx_indexs:, sign_key:)
    prev_tx_indexs.each do |prev_tx_index|
      tx.input do |i|
        i.prev_out prev_tx
        i.prev_out_index prev_tx_index
        i.signature_key sign_key
      end
    end
  end

  def addr_indexs_in_tx_out(tx:, address:)
    out = tx.to_hash(with_address: true)['out']
    out.each_index.select { |i| out[i]['address'] == address }
  end
end
