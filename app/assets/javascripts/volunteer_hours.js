$(document).on('ready load', function () {
    'use strict';
    window.addEventListener('load', function() {
        var forms = document.getElementsByClassName('needs-validation');
        var validation = Array.prototype.filter.call(forms, function(form) {
            form.addEventListener('submit', function(event) {
                if (form.checkValidity() === false) {
                } else{
                    var name = $("input#name").val();
                    var email = $("input#email").val();
                    var phone = $("input#phone").val();
                    var message = $("textarea#message").val();
                    var firstName = name; // For Success/Failure Message
                    // Check for white space in name for Success/Fail message
                    if (firstName.indexOf(' ') >= 0) {
                        firstName = name.split(' ').slice(0, -1).join(' ');
                    }
                    var $this = $("button#sendMessageButton");
                    $this.prop("disabled", true); // Disable submit button until AJAX call is complete to prevent duplicate messages
                    $.ajax({
                        url: '/send_contact_info',
                        type: "POST",
                        data: {
                            name: name,
                            phone: phone,
                            email: email,
                            message: message
                        },
                        cache: false,
                        success: function() {
                            // Success message
                            $('#success').html("<div class='alert alert-success'>");
                            $('#success > .alert-success').html("<button type='button' class='close' data-dismiss='alert' aria-hidden='true'>&times;")
                                .append("</button>");
                            $('#success > .alert-success')
                                .append("<strong>Sua mensagem foi enviada. Entraremos em contato em breve. </strong>");
                            $('#success > .alert-success')
                                .append('</div>');
                            //clear all fields
                            // $('#contactForm').trigger("reset");
                        },
                        error: function() {
                            // Fail message
                            $('#success').html("<div class='alert alert-danger'>");
                            $('#success > .alert-danger').html("<button type='button' class='close' data-dismiss='alert' aria-hidden='true'>&times;")
                                .append("</button>");
                            $('#success > .alert-danger').append($("<strong>").text("Desculpe " + firstName + ", parece que os servers não estão respondendo. Por favor tentar mais tarde."));
                            $('#success > .alert-danger').append('</div>');
                            //clear all fields
                            // $('#contactForm').trigger("reset");
                        },
                    });
                }
                event.preventDefault();
                event.stopPropagation();
                form.classList.add('was-validated');
            }, false);
        });
    }, false);
});