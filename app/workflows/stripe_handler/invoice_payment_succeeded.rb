module StripeHandler

  # これまでのところ存在している購読プロセスでは、invoice.payment_succeededイベントを取得したい。今のところサブスクリプションの金額を調整する理由がないので、invoice.createdイベントはあまり興味がありませんし、charge.succeededイベントはキャッチするには広すぎるイベントのように思えます。(Stripeはサブスクリプションに関連したものだけでなく、チャージが成功するたびにコールバックを送信します)。
  # このイベントの捕捉を開始するために必要なのは、適切な名前のクラスを作成することです。そして、コンストラクタの引数としてイベントを受け取り、実行メッセージに応答し、最後に成功に応答する必要があります。
  class InvoicePaymentSucceeded

    attr_accessor :event, :success, :payment

    def initialize(event)
      @event = event
      @success = false
    end

    def run
      Subscription.transaction do
        return unless event
        subscription.active!
        subscription.update_end_date
        @payment = Payment.create!(
          user_id: user.id, price_cents: invoice.amount_due,
          status: "succeeded", reference: Payment.generate_reference,
          payment_method: "stripe", response_id: invoice.charge,
          full_response: charge.to_json)
        payment.payment_line_items.create!(
          buyable: subscription, price_cents: invoice.amount_due)
        @success = true
      end
    end

    def invoice
      @event.data.object
    end

    def subscription
      @subscription ||= Subscription.find_by(remote_id: invoice.subscription)
    end

    def user
      @user ||= User.find_by(stripe_id: invoice.customer)
    end

    def charge
      @charge ||= Stripe::Charge.retrieve(invoice.charge)
    end
  end
end
