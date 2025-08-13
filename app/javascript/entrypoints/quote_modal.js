function parseVal(el) {
  const valStr = el.value !== undefined ? el.value : el.textContent;
  const val = parseFloat(valStr);
  return isNaN(val) ? 0.0 : val;
}

function calculateTotal() {
  let total = 0.0;

  document.querySelectorAll(".card").forEach((card) => {
    let baseFee = parseVal(card.querySelector(".base-fee") || { value: 0 });
    let qty = parseVal(card.querySelector(".service-qty") || { value: 0 });
    let pricePer = parseVal(
      card.querySelector(".service-price") || { value: 0 },
    );

    let serviceTotal = qty * pricePer;
    total += baseFee + serviceTotal;

    card.querySelectorAll(".option-price").forEach((opt) => {
      total += parseVal(opt);
    });
  });

  document.querySelectorAll(".line-item").forEach((row) => {
    const priceInput = row.querySelector(".line-item-price");
    if (priceInput) {
      total += parseVal(priceInput);
    }
  });

  document.getElementById("quote-total-value").textContent = total.toFixed(2);
}

function initEventListeners() {
  document.querySelectorAll(".money-input, .service-qty").forEach((el) => {
    el.addEventListener("input", calculateTotal);
    el.addEventListener("blur", () => {
      if (el.value !== "") el.value = parseVal(el).toFixed(2);
      calculateTotal();
    });
  });

  document.querySelectorAll(".line-item-delete").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      e.target.closest(".line-item").remove();
      calculateTotal();
    });
  });

  const newLineItemBtn = document.getElementById("new-line-item");
  if (newLineItemBtn) {
    newLineItemBtn.addEventListener("click", () => {
      const template = document.getElementById("new-line-item-template");
      if (template) {
        const clone = template.cloneNode(true);
        clone.removeAttribute("id");
        clone.style.display = "flex";

        clone.innerHTML = clone.innerHTML.replace(/__INDEX__/g, Date.now());

        clone.querySelectorAll("input").forEach((input) => (input.value = ""));

        clone
          .querySelector(".line-item-delete")
          .addEventListener("click", (e) => {
            e.target.closest(".line-item").remove();
            calculateTotal();
          });

        document.getElementById("line-items-container").appendChild(clone);

        clone.querySelectorAll(".line-item-price").forEach((input) => {
          input.addEventListener("input", calculateTotal);
          input.addEventListener("blur", () => {
            if (input.value !== "") input.value = parseVal(input).toFixed(2);
            calculateTotal();
          });
        });
      }
    });
  }
}

const modal = document.getElementById("quote-modal");
modal.addEventListener("shown.bs.modal", () => {
  initEventListeners();
  calculateTotal();
});
