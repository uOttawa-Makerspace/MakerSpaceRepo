// The words a page gives its calendar element (CalendarHelper#calendar_texts_data
// over config/locales/calendars.yml), in English and in French.
export const CALENDAR_TEXTS = {
  en: {
    hints: {
      closeHint: "Close",
      timeHint: "Time",
      eventHint: "Event",
      navLinkHint: "Go to $0",
    },
    daysButtonHints: { prev: "Previous days", next: "Next days" },
    showMyShiftsOnly: "Show My Shifts Only",
    showAllShifts: "Show All Shifts",
    enableOverlap: "Enable Event Overlap",
    disableOverlap: "Disable Event Overlap",
    showWeekends: "Show Weekends",
    hideWeekends: "Hide Weekends",
    publishDrafts: {
      timeGridWeek: "Publish This Week's Drafts",
      dayGridMonth: "Publish This Month's Drafts",
    },
    deleteDrafts: {
      timeGridWeek: "Delete This Week's Drafts",
      dayGridMonth: "Delete This Month's Drafts",
    },
    hours: "{hours} hrs",
    book: "Book",
  },
  fr: {
    hints: {
      closeHint: "Fermer",
      timeHint: "Heure",
      eventHint: "Événement",
      navLinkHint: "Aller au $0",
    },
    daysButtonHints: { prev: "Jours précédents", next: "Jours suivants" },
    showMyShiftsOnly: "Afficher seulement mes quarts",
    showAllShifts: "Afficher tous les quarts",
    enableOverlap: "Activer le chevauchement des événements",
    disableOverlap: "Désactiver le chevauchement des événements",
    showWeekends: "Afficher les fins de semaine",
    hideWeekends: "Masquer les fins de semaine",
    publishDrafts: {
      timeGridWeek: "Publier les brouillons de cette semaine",
      dayGridMonth: "Publier les brouillons de ce mois-ci",
    },
    deleteDrafts: {
      timeGridWeek: "Supprimer les brouillons de cette semaine",
      dayGridMonth: "Supprimer les brouillons de ce mois-ci",
    },
    hours: "{hours} h",
    book: "Réserver",
  },
};

// The data attribute as the server writes it, for a page fixture.
export function textsAttribute(lang = "en") {
  const json = JSON.stringify(CALENDAR_TEXTS[lang]);
  return `data-calendar-texts="${json.replace(/&/g, "&amp;").replace(/"/g, "&quot;")}"`;
}
