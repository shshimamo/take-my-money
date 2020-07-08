# 大まかに購入ステップは３つ
# - 購入前のチェックリスト。必要なデータが揃っているか、データが有効なフォーマットになっているか
# - 実際のAPIコールでは成功していることを確認する
# - PAIコールに対するレスポンスは、通常レスポンスの重要な部分を保存し、いくつかの簿記を行い、成功した結果をユーザーに通知する

# 失敗への対応はどの段階で失敗したかによって異なる
# - 事前購入に失敗した場合は、APIコールを行わず、おそらくデータベースの変更も行わず、ユーザーをクレジットカードフォームに戻して再試行します。
# - APIコールが失敗した場合は、通常はフライト前のデータ変更の一部またはすべてを元に戻し、ユーザーに通知し、通常はユーザーをクレジットカードフォームに戻して再試行します。
# - 支払いは成功したが、その後のコードが失敗した場合はまずいケースです。このエラーを捕捉して通知が送信されることを確認してください。場合によっては、自動的に支払いを返金する必要があるかもしれません。

# 失敗や予期せぬ結果を軽減しようとするとき、問題の発生原因に焦点を当てるよりも、問題の顕在化に焦点を当てたほうが実りがあることが多い。最終的には理由を追いかける必要があるが、対応時にはどうやってそこにたどり着いたかよりも、予期せぬ状態に焦点を当てたいものです。
class PaymentsController < ApplicationController

  def show
    @reference = params[:id]
    @payment = Payment.find_by(reference: @reference)
  end

  def create
    normalize_purchase_amount
    workflow = run_workflow(params[:payment_type], params[:purchase_type])
    if workflow.success
      redirect_to workflow.redirect_on_success_url ||
        payment_path(id: @reference || workflow.payment.reference)
    else
      redirect_to shopping_cart_path
    end
  end

  private

  def run_workflow(payment_type, purchase_type)
    case purchase_type
    when "SubscriptionCart" then stripe_subscription_workflow
    when "ShoppingCart" then payment_workflow(payment_type)
    end
  end

  # 単発購入
  def payment_workflow(payment_type)
    case payment_type
    when "paypal" then paypal_workflow
    when "credit" then stripe_workflow
    when "cash" then cash_workflow
    when "invoice" then cash_workflow
    end
  end

  def pick_user
    if current_user.admin? && params[:user_email].present?
      User.find_or_create_by(email: params[:user_email])
    else
      current_user
    end
  end

  def cash_workflow
    workflow = CashPurchasesCart.new(
      user: pick_user,
      purchase_amount_cents: params[:purchase_amount_cents],
      expected_ticket_ids: params[:ticket_ids],
      shopping_cart: current_cart)
    workflow.run
    workflow
  end

  def normalize_purchase_amount
    return if params[:purchase_amount].blank?
    params[:purchase_amount_cents] =
      params[:purchase_amount].to_f * 100
  end

  # サブスクリプション
  # クライアントページでは、ユーザーはサブスクリプションプランを選択し、クレジットカード情報を入力します。以前と同じように、フォームが送信される前に、クライアントブラウザからStripeに連絡を取り、トークンを受け取ります。また、以前と同様に、クレジットカードのフォームが完了すると、そのトークンを受け取り、サーバーに送り返します。
  # Customerオブジェクトが作成され、トークンと関連付けられます。これでサブスクリプションのトランザクションは完了し、顧客のクレジットカードへの定期的なチャージを継続するかどうかはStripe次第です。Stripeには支払いイベントについての通知もお願いしています。(このトラッキングはウェブフックを介して行われますが、131ページの「ウェブフックの設定」で説明します)。
  def stripe_subscription_workflow
    workflow = CreatesSubscriptionViaStripe.new(user: pick_user,
      expected_subscription_id: params[:subscription_ids].first,
      token: StripeToken.new(**card_params))
    workflow.run
    workflow
  end

  def paypal_workflow
    workflow = PreparesCartForPayPal.new(
      user: current_user,
      purchase_amount_cents: params[:purchase_amount_cents],
      expected_ticket_ids: params[:ticket_ids],
      shopping_cart: current_cart)
    workflow.run
    workflow
  end

  def stripe_workflow
    @reference = Payment.generate_reference
    PreparesCartForStrjpeJob.perform_later(
      user: current_user,
      params: card_params,
      purchase_amount_cents: params[:purchase_amount_cents],
      expected_ticket_ids: params[:ticket_ids],
      payment_reference: @reference,
      shopping_cart: current_cart)
  end

  def card_params
    params.permit(
      :credit_card_number, :expiration_month,
      :expiration_year, :cvc,
      :stripe_token).to_h.symbolize_keys
  end
end
