import Sortable from "sortablejs";

const sortables = []

document.addEventListener("turbolinks:load", () => {
    const reorderElements = [...document.getElementsByClassName('reorder')];
    reorderElements.forEach((reorderElement) => {
        reorderElement.addEventListener('click', (e => {
            let sortable = sortables.find(el => el.name === e.target.dataset.accordion);
            if (!sortable || !sortable.value) {
                sortable = Sortable.create(document.getElementById(e.target.dataset.accordion), {
                    disabled: !e.target.checked,
                    onEnd: (e) => {
                        fetch('/learning_area/reorder', {
                            method: "PUT",
                            headers: {
                                'Accept': 'application/json',
                                'Content-Type': 'application/json'
                            },
                            body: JSON.stringify({data: [...e.from.children].map(c => c.dataset.id), format: 'json'})
                        }).catch((error) => {
                            console.log('An error occurred: ' + error.message);
                        });
                    }
                })
                sortables.push({
                    name: e.target.dataset.accordion,
                    value: sortable
                })
            } else {
                sortable.value.option('disabled', !e.target.checked)
            }
        }))
    })
});