import React from "react";
import PropTypes from "prop-types";

import { withRouter, routerShape } from "found";
import map from "lodash/map";
import get from "lodash/get";
import { createFragmentContainer, graphql } from "react-relay";
import { withStyles } from "material-ui/styles";
import Paper from "material-ui/Paper";
import Button from "material-ui/Button";
import Typography from "material-ui/Typography";

import Checkbox from "material-ui/Checkbox";

import EventsListItem from "./EventsListItem";
import EventsContainerMenu from "./EventsContainerMenu";

const styles = theme => ({
  eventsContainer: {
    marginTop: 16,
    marginBottom: 16,
  },
  tableHeader: {
    padding: "20px 0 16px",
    backgroundColor: theme.palette.primary.light,
    color: theme.palette.primary.contrastText,
    display: "flex",
    alignItems: "center",
  },
  tableHeaderButton: {
    marginLeft: 16,
    display: "flex",
  },
  checkbox: {
    marginTop: -4,
    width: 24,
    height: 24,
    color: theme.palette.primary.contrastText,
  },
  altMenuButton: {
    color: theme.palette.primary.contrastText,
    padding: "0 0 1px",
    minHeight: 20,
    "&:hover": { backgroundColor: "inherit" },
  },
  hidden: {
    display: "none",
  },
});

class EventsContainer extends React.Component {
  static propTypes = {
    // eslint-disable-next-line react/forbid-prop-types
    classes: PropTypes.object.isRequired,
    viewer: PropTypes.shape({ checkEvents: PropTypes.object }).isRequired,
    router: routerShape.isRequired,
  };

  // constructor is needed in order to set the inital state of the checkbox for each
  // event item. We need to know how many events will be displayed before render.
  constructor(props) {
    super(props);

    this.state = {
      rowState: [],
      switchHeader: false,
      filters: [],
    };
    const { viewer } = props;
    const eventsLength = get(viewer, "events.edges", []).length;
    for (let i = 0; i < eventsLength; i += 1) {
      this.state.rowState[i] = false;
    }
  }

  // click checkbox for all items in list
  selectAll = () => {
    const newState = [];
    // if there's any number of boxes checked, show bulk actions button
    if (
      this.state.rowState.includes(false) ||
      (this.state.rowState.includes(true) &&
        this.state.rowState.includes(false))
    ) {
      for (let i = 0; i < this.state.rowState.length; i += 1) {
        newState[i] = true;
      }
      this.setState({ switchHeader: true });
    } else {
      // unhide the default header buttons only if there's no checks
      for (let i = 0; i < this.state.rowState.length; i += 1) {
        newState[i] = false;
      }
      this.setState({ switchHeader: false });
    }
    this.setState({ rowState: newState });
  };

  // click single checkbox
  selectCheckbox = i => () => {
    this.state.rowState[i] = !this.state.rowState[i];
    // only show the default header buttons if there's none selected
    if (this.state.rowState.includes(true)) {
      this.setState({ switchHeader: true });
    } else {
      this.setState({ switchHeader: false });
    }
    this.forceUpdate();
  };

  resolve = () => {
    // for each item set as true in rowState -> resolve
  };

  silence = () => {
    // silence each item that is true in rowState
  };

  // TODO revist this later
  requeryEntity = newValue => {
    this.props.router.push(
      `${window.location.pathname}?filter=event.Entity.ID=='${newValue}'`,
    );
  };

  requeryCheck = newValue => {
    this.props.router.push(
      `${window.location.pathname}?filter=event.Check.Name=='${newValue}'`,
    );
  };

  requeryStatus = newValue => {
    this.props.router.push(
      `${window.location.pathname}?filter=event.Check.Status==${newValue}`,
    );
  };

  render() {
    const { classes, viewer } = this.props;

    // TODO maybe revisit for pagination issues
    const events = get(viewer, "events.edges", []);
    const entities = get(viewer, "entities.edges", []);
    const entityNames = map(entities, edge => edge.node.name);
    const checks = get(viewer, "checks.edges", []);
    const checkNames = [...map(checks, edge => edge.node.name), "keepalive"];
    const statuses = [0, 1, 2, 3];

    return (
      <Paper className={classes.eventsContainer}>
        <div className={classes.tableHeader}>
          <span className={classes.tableHeaderButton}>
            <Checkbox
              color="secondary"
              className={classes.checkbox}
              onClick={this.selectAll}
              checked={this.state.switchHeader}
            />
          </span>
          <div style={this.state.switchHeader ? {} : { display: "none" }}>
            <Button className={classes.altMenuButton} onClick={this.silence}>
              <Typography type="button">Silence</Typography>
            </Button>
            <Button className={classes.altMenuButton} onClick={this.resolve}>
              <Typography type="button">Resolve</Typography>
            </Button>
          </div>
          <div style={this.state.switchHeader ? { display: "none" } : {}}>
            <EventsContainerMenu
              onSelectValue={this.requeryEntity}
              label="Entity"
              contents={entityNames}
            />
            <EventsContainerMenu
              onSelectValue={this.requeryCheck}
              label="Check"
              contents={checkNames}
            />
            <EventsContainerMenu
              onSelectValue={this.requeryStatus}
              label="Status"
              contents={statuses}
              icons
            />
          </div>
        </div>
        {/* TODO pass in resolve and silence functions to reuse for single actions
            the silence dialog is the same, just maybe some prefilled options for list */}
        {events.map((event, i) => (
          <EventsListItem
            key={event.node.id}
            event={event.node}
            onChange={this.selectCheckbox(i)}
            checked={this.state.rowState[i]}
          />
        ))}
      </Paper>
    );
  }
}

export default createFragmentContainer(
  withStyles(styles)(withRouter(EventsContainer)),
  graphql`
    fragment EventsContainer_viewer on Viewer {
      entities(first: 1000) {
        edges {
          node {
            name
          }
        }
      }
      checks(first: 1000) {
        edges {
          node {
            name
          }
        }
      }
      events(first: 1000, filter: $filter) {
        edges {
          node {
            id
            ...EventsListItem_event
          }
        }
        pageInfo {
          hasNextPage
        }
      }
    }
  `,
);
