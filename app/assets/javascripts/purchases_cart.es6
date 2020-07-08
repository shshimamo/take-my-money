// P50
// 実際のブラウザ出力と相互作用する DOM と jQuery メソッドの周りの薄いラッパーです
class CheckoutForm {

  static cardswipe(data) {
    new CheckoutForm().cardswipe(data)
  }

  cardswipe(data) {
    this.numberField().val(data.account)
    this.expiryField().val(`${data.expMonth}/${data.expYear}`)
    this.cvcField().focus()
  }

  format() {
    this.numberField().payment("formatCardNumber")
    this.expiryField().payment("formatCardExpiry")
    this.cvcField().payment("formatCardCVC")
    this.disableButton()
  }

  form() { return $("#payment-form") }

  validFields() { return this.form().find(".valid-field") }

  numberField() { return this.form().find("#credit_card_number") }

  expiryField() { return this.form().find("#expiration_date") }

  cvcField() { return this.form().find("#cvc") }

  displayStatus() {
    this.displayFieldStatus(this.numberField(), this.isNumberValid())
    this.displayFieldStatus(this.expiryField(), this.isExpiryValid())
    this.displayFieldStatus(this.cvcField(), this.isCvcValid())
    this.cardImage().attr("src", this.imageUrl())
    this.buttonStatus()
  }

  // フィールドに対してクラスを付与する
  displayFieldStatus(field, valid) {
    const parent = field.parents(".form-group")
    if (field.val() === "") {
      parent.removeClass("has-error")
      parent.removeClass("has-success")
    }
    parent.toggleClass("has-error", !valid)
    parent.toggleClass("has-success", valid)
  }

  isNumberValid() {
    return $.payment.validateCardNumber(this.numberField().val())
  }

  isExpiryValid() {
    const date = $.payment.cardExpiryVal(this.expiryField().val())
    return $.payment.validateCardExpiry(date.month, date.year)
  }

  isCvcValid() { return $.payment.validateCardCVC(this.cvcField().val()) }

  cardImage() { return $("#card-image") }

  imageUrl() { return `/assets/creditcards/${this.cardType()}.png` }

  cardType() { return $.payment.cardType(this.numberField().val()) || "credit" }

  buttonStatus() {
    return this.valid() ? this.enableButton() : this.disableButton()
  }

  // 3つのフィールドがすべて有効であるか
  valid() {
    return this.isNumberValid() && this.isExpiryValid() && this.isCvcValid()
  }

  button() { return this.form().find("#purchase") }

  disableButton() { this.button().toggleClass("disabled", true) }

  enableButton() { this.button().toggleClass("disabled", false) }

  isEnabled() { return !this.button().hasClass("disabled") }

  isButtonDisabled() { return this.button().prop("disabled") }

  paymentTypeRadio() { return $(".payment-type-radio") }

  selectedPaymentType() { return $("input[name=payment_type]:checked").val() }

  creditCardForm() { return $("#credit-card-info") }

  isPayPal() { return this.selectedPaymentType() === "paypal" }

  isCreditCard() { return this.selectedPaymentType() === "credit" }

  setCreditCardVisibility() {
    this.creditCardForm().toggleClass("hidden", !this.isCreditCard())
  }

  setButtonStatus() {
    !this.isCreditCard() ? this.enableButton() : this.buttonStatus()
  }

  submit() { this.form().get(0).submit() }

  appendHidden(name, value) {
    const field = $("<input>")
      .attr("type", "hidden")
      .attr("name", name)
      .val(value)
    this.form().append(field)
  }
}

// P51
// Stripeからトークンを取得したら、それを実際のフォームDOMに埋め込み、通常通りにフォームを送信してイベントを完了させます。チェックアウトフォームクラスで appendHidden と submit を定義し、TokenHandler から呼び出すことができるようにしました。フォームが送信します。カードデータにはマークアップの名前フィールドがないので、トークンと価格のhiddenフィールドのみを送信します。 そしてサーバー上のデータに戻ります。
class TokenHandler {
  static handle(status, response) {
    new TokenHandler(status, response).handle()
  }

  constructor(status, response) {
    this.checkoutForm = new CheckoutForm()
    this.status = status
    this.response = response
  }

  isError() { return this.response.error }

  // Stripe APIから取得したレスポンスがエラーであれば(this.response.error)画面にそれを表示するだけ
  handle() {
    if (this.isError()) {
      this.checkoutForm.appendError(this.response.error.message)
      this.checkoutForm.enableButton()
    } else {
      this.checkoutForm.appendHidden("stripe_token", this.response.id)
      this.checkoutForm.submit()
    }
  }
}

// P49 (これがStripeFormだったのかな)
// StripeFormクラスは、送信イベントのハンドラをセットアップする小さなラッパーです。
class PaymentFormHandler {

  constructor() {
    this.checkoutForm = new CheckoutForm()
    this.checkoutForm.format()
    this.initEventHandlers()
    this.initPaymentTypeHandler()
  }

  initEventHandlers() {
    this.checkoutForm.form().submit(event => {
      if (this.checkoutForm.isCreditCard()) {
        this.handleSubmit(event)
      }
    })
    // いずれかのフィールドにキーを入力するとバリデーションチェックが走る
    this.checkoutForm.validFields().keyup(() => {
      this.checkoutForm.displayStatus()
    })
  }

  initPaymentTypeHandler() {
    this.checkoutForm.paymentTypeRadio().click(() => {
      this.checkoutForm.setCreditCardVisibility()
      this.checkoutForm.setButtonStatus()
    })
  }

  // handleSubmitは3つのことをします。
  handleSubmit(event) {
    // event.preventDefault()は、このメソッドの最後にフォームが自動的に送信されないようにするためのものです。Stripeからの連絡が来るまでフォームが送信されないようにしたいのです。falseを返すことで、それ以上のイベントの伝播を防ぐことができます。
    event.preventDefault()

    // CheckoutFormを呼び出して、ボタンが無効になっているかどうかを確認します。もしそうであれば、チェックアウト中であることを示しており、再送信ではなく終了します
    // CheckoutFormを呼び出してボタンを無効にし、ユーザーがボタンをクリックしてフォームを2回送信することを防ぎます。
    if (this.checkoutForm.isButtonDisabled()) {
      return false
    }
    this.checkoutForm.disableButton()

    // Stripe.jsライブラリで定義されているStripe.card.createTokenを呼び出しますが、これは先ほどサーバー側で使用したStripe::Token#createメソッドのJavaScript版です。これはStripeサーバーにクレジットカード情報を送信し、トークンを返します。
    Stripe.card.createToken(this.checkoutForm.form(), TokenHandler.handle)
    // Stripe.card.createTokenメソッドは2つの引数を取ります。1つ目は、データストライプ属性を持つすべてのフィールドを含むフォーム要素です。Stripeライブラリは、フォームから自動的にクレジットカードデータを取得します。2つ目の引数は、Stripe APIがトークンデータを返してきたときに呼び出されるコールバックメソッドです。私たちの場合は、TokenHandlerクラスのクラスメソッドを使用しています。

    return false
  }
}

$(() => {
  if ($("#admin_credit_card_info").size() > 0) {
    $.cardswipe({
      firstLineOnly: false,
      success: CheckoutForm.cardswipe,
      parsers: ["visa", "amex", "mastercard", "discover", "generic"],
      debug: false,
    })
  }
  if ($(".credit-card-form").size() > 0) {
    return new PaymentFormHandler()
  }

  return null
})
