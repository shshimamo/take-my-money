# 実際にサブスクリプションを作成して課金を開始させるには、Stripeで顧客オブジェクトを作成し、それをプランに関連付ける必要があります。Stripeはその顧客とプランの関係のための内部サブスクリプションオブジェクトを作成します。そのため、データベースとStripeのAPIの間でユーザーオブジェクトを連携させる必要があります。
# Stripeに顧客を登録するには、「おい、Stripe、顧客IDをくれ」と言うだけです（厳密にはStripe::Customer.create）。Stripeの顧客が作成されると、実際にその顧客をStripeのダッシュボードで確認することができます。Stripe IDを顧客レコードに追加することで、顧客レコードを協調させるのは私たちの責任です。

class StripeCustomer

  attr_accessor :user

  delegate :subscriptions, :id, to: :remote_customer

  def initialize(user)
    @user = user
  end

  # StripeCustomerクラスは、オブジェクト作成の詳細を隠すために使用されます。具体的には、usersがすでにStripeに登録されている場合とそうでない場合では、異なるStripe APIコールを行う必要があることを隠しています
  def remote_customer
    @remote_customer ||= begin
      if user.stripe_id
        Stripe::Customer.retrieve(user.stripe_id)
      else
        Stripe::Customer.create(email: user.email).tap do |remote_customer|
          user.update!(stripe_id: remote_customer.id)
        end
      end
    end
  end

  def valid?
    remote_customer.present?
  end

  def find_subscription_for(plan)
    subscriptions.find { |s| s.plan.id == plan.remote_id }
  end

  def add_subscription(subscription)
    remote_subscription = remote_customer.subscriptions.create(
      plan: subscription.remote_plan_id)
    subscription.update!(remote_id: remote_subscription.id)
  end

  def source=(token)
    remote_customer.source = token.id
    remote_customer.save
  end
end
