var client = ShopifyBuy.buildClient({
  domain: 'uottawa-makerspace.myshopify.com',
  storefrontAccessToken: '907521a2176d178e041f542c129f52b1',
});
var ui = ShopifyBuy.UI.init(client);
ui.createComponent('product', {
  id: 4359597129784,
  node: document.getElementById('cc-money-shopify')
});