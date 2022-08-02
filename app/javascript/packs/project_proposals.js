
if (document.getElementById("project_proposal_categories")) {
    if (!document.getElementById("project_proposal_categories").tomselect) {
        new TomSelect("#project_proposal_categories", {
            plugins: ['remove_button'],
            maxItems: 5
        })
    }
}
