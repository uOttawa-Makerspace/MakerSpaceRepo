document.addEventListener("turbolinks:load", function () {
    if (document.getElementById("project_proposal_categories")) {
        new TomSelect("#project_proposal_categories", {
            plugins: ['remove_button'],
            maxItems:5
        })
    }
    if (document.getElementById("project_proposal_equipments")) {
        new TomSelect("#project_proposal_equipments", {
            plugins: ['remove_button'],
            maxItems:5
        })
    }
});