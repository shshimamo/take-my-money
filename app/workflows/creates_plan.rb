# シンプルなワークフローを使ってプランを作成し、Stripeと連携させることができます。このワークフローは、入力されたパラメータの束を受け取り、通貨などのデフォルト値とともにStripeに渡すだけです。
class CreatesPlan

  attr_accessor :remote_id, :product, :nickname, :price_cents, :interval,
  :tickets_allowed, :ticket_category, :plan

  def initialize(remote_id:, product:, nickname:, price_cents:, interval:,
      interval_count:, tickets_allowed:, ticket_category:)
    @remote_id = remote_id
    @product = product
    @nickname = nickname
    @price_cents = price_cents
    @interval = interval
    @interval_count = interval_count
    @tickets_allowed = tickets_allowed
    @ticket_category = ticket_category
  end

  # Stripeの作成が成功したら、次はローカルプランの作成です。Stripeの作成が成功しなかった場合は、Stripe gemが例外を投げて全体が停止します。
  def run
    remote_plan = Stripe::Plan.create(
      id: remote_id, product: product, amount: price_cents, currency: "usd",
      interval: interval, interval_count: 1, nickname: nickname)
    self.plan = Plan.create(
      remote_id: remote_plan.id, nickname: nickname, price_cents: price_cents,
      interval: interval, interval_count: 1, tickets_allowed: tickets_allowed,
      ticket_category: ticket_category, status: :active)
  end
end
