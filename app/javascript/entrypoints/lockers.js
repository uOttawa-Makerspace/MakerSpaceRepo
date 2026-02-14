import TomSelect from "tom-select";

function handleLinkInput(evt) {
  const url = this.value;
  // https://admin.shopify.com/store/uottawa-makerspace/products/10478024917048?link_source=search
  const match = url.match(/\/products\/(\d+)/i);
  const id = match ? match[1] : null;

  document.querySelector("#value").value = id;
}

document.addEventListener("turbo:load", function () {
  new TomSelect("select.locker-variant-select", {
    render: {
      option: function (data, escape) {
        data = JSON.parse(data.data);
        let title = escape(data.displayName);
        let sku = escape(data.sku);
        let price = escape(data.price);
        return `<div>
                  <span><b>Display Name:</b> ${title}</span> <br />
                  <span><b>SKU:</b> <code>${sku}</code></span> <br />
                  <span><b>Price:</b> <code>${price}</code></span>
                </div>`;
      },
    },
  });

  let lockerProductLinkInput = document.querySelector("#shopifyProductLink");
  if (lockerProductLinkInput) {
    lockerProductLinkInput.addEventListener("input", handleLinkInput);
  }
});
