class PreparesCart

  # 共通点: ユーザーや金額など購入に必要な属性
  attr_accessor :user, :purchase_amount_cents, :purchase_amount,
    :success, :payment, :expected_ticket_ids, :payment_reference,
    :shopping_cart

  def initialize(user: nil, purchase_amount_cents: nil,
      expected_ticket_ids: "", payment_reference: nil,
      shopping_cart: nil)
    @user = user
    @shopping_cart = shopping_cart
    @purchase_amount = Money.new(purchase_amount_cents)
    @expected_ticket_ids = expected_ticket_ids.split(" ").map(&:to_i).sort
    @payment_reference = payment_reference
    @success = false
  end

  delegate :discount_code, to: :shopping_cart

  def price_calculator
    @price_calculator ||= PriceCalculator.new(
      tickets, discount_code, shopping_cart.shipping_method,
      user: user, address: shopping_cart.address,
      tax_id: "cart_#{shopping_cart.id}")
  end

  delegate :total_price, to: :price_calculator

  def amount_valid?
    return true if user.admin?
    purchase_amount == total_price
  end

  def tickets_valid?
    expected_ticket_ids == tickets.map(&:id).sort
  end

  # - 入力の有効性をチェック
  #   - ユーザー入力からの購入金額と計算された価格が一致するか
  #   - チケットIDのリストもチェック
  def pre_purchase_valid?
    amount_valid? && tickets_valid?
  end

  # 共通点: ユーザーからチケットの一覧を取得する方法の定義
  def tickets
    @tickets ||= @user.tickets_in_cart.select do |ticket|
      ticket.payment_reference == payment_reference
    end
  end

  def existing_payment
    Payment.find_by(reference: payment_reference)
  end

  # 共通点: 基本的なワークフロー(チケット更新、支払い(payment)作成、リモートAPIとのやりとり、など)
  def run
    Payment.transaction do
      raise PreExistingPaymentException.new(payment) if existing_payment
      unless pre_purchase_valid?
        # 入力値の検証に失敗した場合すぐに抜け出す
        raise ChargeSetupValidityException.new(
          user: user,
          expected_purchase_cents: purchase_amount.to_i,
          expected_ticket_ids: expected_ticket_ids)
      end
      update_tickets
      create_payment
      clear_cart
      on_success
    end
  rescue
    on_failure
    raise
  end

  def clear_cart
    shopping_cart.destroy
  end

  def redirect_on_success_url
    nil
  end

  # 共通点: 購入のための属性(payment_attributes)からPaymentオブジェクトを作成する基本ロジック
  def create_payment
    self.payment = existing_payment || Payment.new
    payment.update!(payment_attributes)
    payment.create_line_items(tickets)
    @success = payment.valid?
  end

  def payment_attributes
    {user_id: user.id, price_cents: purchase_amount.cents,
     status: "created", reference: Payment.generate_reference,
     discount_code_id: discount_code&.id,
     discount: price_calculator.discount,
     partials: price_calculator.breakdown,
     shipping_method: shopping_cart.shipping_method,
     shipping_address: shopping_cart.address}
  end

  def success?
    success
  end

  def on_failure
    unpurchase_tickets
  end

  def unpurchase_tickets
    tickets.each(&:waiting!)
  end
end
