# encoding: UTF-8
# frozen_string_literal: true

class Deposit < ActiveRecord::Base
  STATES = %i[submitted canceled rejected accepted].freeze

  include AASM
  include AASM::Locking
  include BelongsToCurrency
  include BelongsToMember
  include TIDIdentifiable
  include FeeChargeable

  has_paper_trail on: [:update, :destroy]

  acts_as_eventable prefix: 'deposit', on: %i[create update]

  validates :tid, :aasm_state, :type, presence: true
  validates :completed_at, presence: { if: :completed? }

  scope :recent, -> { order(id: :desc) }

  before_validation { self.completed_at ||= Time.current if completed? }

  aasm whiny_transitions: false do
    state :submitted, initial: true
    state :canceled
    state :rejected
    state :accepted
    event(:cancel) { transitions from: :submitted, to: :canceled }
    event(:reject) { transitions from: :submitted, to: :rejected }
    event :accept do
      transitions from: :submitted, to: :accepted
      after { account.plus_funds(amount) }
    end
  end

  def account
    member&.ac(currency)
  end

  def sn
    member&.sn
  end

  def sn=(sn)
    self.member = Member.find_by_sn(sn)
  end

  def as_json_for_event_api
    { tid:                      tid,
      uid:                      member.uid,
      currency:                 currency_id,
      amount:                   amount.to_s('F'),
      state:                    aasm_state,
      created_at:               created_at.iso8601,
      updated_at:               updated_at.iso8601,
      completed_at:             completed_at&.iso8601,
      blockchain_address:       address,
      blockchain_txid:          txid,
      blockchain_confirmations: confirmations }
  end

  def completed?
    !submitted?
  end
end

# == Schema Information
# Schema version: 20180529125011
#
# Table name: deposits
#
#  id            :integer          not null, primary key
#  member_id     :integer          not null
#  currency_id   :string(10)       not null
#  amount        :decimal(32, 16)  not null
#  fee           :decimal(32, 16)  not null
#  address       :string(64)
#  txid          :string(128)
#  txout         :integer
#  aasm_state    :string(30)       not null
#  confirmations :integer          default(0), not null
#  type          :string(30)       not null
#  tid           :string(64)       not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  completed_at  :datetime
#
# Indexes
#
#  index_deposits_on_aasm_state_and_member_id_and_currency_id  (aasm_state,member_id,currency_id)
#  index_deposits_on_currency_id                               (currency_id)
#  index_deposits_on_currency_id_and_txid_and_txout            (currency_id,txid,txout) UNIQUE
#  index_deposits_on_member_id_and_txid                        (member_id,txid)
#  index_deposits_on_tid                                       (tid)
#  index_deposits_on_type                                      (type)
#
